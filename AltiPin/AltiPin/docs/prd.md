
# AltiPin 产品技术规格说明书 (PRD & Tech Spec)

**项目名称**：AltiPin
**产品定位**：纯本地、零登录、无服务器存储的自动化轨迹与海拔记录工具，支持基于无状态服务器的团队实时位置共享。

---

## 一、 系统架构与技术栈

### 1. 客户端 (iOS)
* **开发语言**：Swift 5.10+
* **UI 框架**：SwiftUI
* **本地数据持久化**：SwiftData（或 CoreData）用于元数据索引；文件系统沙盒（Documents）用于存储标准 `.gpx` 文件。
* **核心框架**：CoreLocation（后台定位）、CoreMotion（运动传感器）、CoreTelephony/Network（弱网状态感知）。

### 2. 服务端 (实时中转)
* **开发语言**：Node.js (TypeScript) 或 Go
* **通信协议**：WebSocket（原生或 Socket.io）
* **数据库**：无。全内存运行（Stateless Relay），数据不落盘。

---

## 二、 本地数据模型与文件 Schema

### 1. SwiftData 元数据模型 (TripEntity)
用于在 App 首页列表展示，不保存具体的经纬度数组，只保存文件指针和统计数据。

```swift
import Foundation
import SwiftData

@Model
final class TripEntity {
    @Attribute(.unique) var id: UUID
    var title: String // 默认形如 "2026-06-13 轨迹" 或用户手动合并后的 "加拿大旅游"
    var dateCreated: Date
    var isMerged: Bool // 是否是用户手动合并的条目
    var subGpxFileNames: [String] // 包含的原始单日 GPX 文件名列表
    
    // 统计数据 (由本地异步解析 GPX 后写入)
    var totalDistance: Double // 单位: 米
    var totalAscent: Double // 累计爬升, 单位: 米
    var maxElevation: Double // 最高海拔
    var startTime: Date
    var endTime: Date

    init(title: String, subGpxFileNames: [String], startTime: Date, endTime: Date) {
        self.id = UUID()
        self.title = title
        self.dateCreated = Date()
        self.subGpxFileNames = subGpxFileNames
        self.totalDistance = 0.0
        self.isMerged = false
        self.totalAscent = 0.0
        self.maxElevation = 0.0
        self.startTime = startTime
        self.endTime = endTime
    }
}
```

### 2. 本地 GPX 文件存储规范
单日自动记录的文件存储在本地 `Documents/Tracks/YYYYMMDD.gpx`。  
格式必须严格遵循标准 **GPX 1.1 协议**，确保可导出至第三方软件：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="AltiPin" xmlns="http://www.topografix.com/GPX/1/1">
    <metadata>
        <time>2026-06-13T00:00:00Z</time>
    </metadata>
    <trk>
        <name>2026-06-13 自动记录</name>
        <trkseg>
            <trkpt lat="49.2827" lon="-123.1207">
                <ele>115.4</ele>
                <time>2026-06-13T10:04:01Z</time>
            </trkpt>
        </trkseg>
    </trk>
</gpx>
```

---

## 三、 核心模块详细设计

### 模块 1：无感单人自动化记录引擎 (Tracking Engine)

#### 1. 核心策略
* 避免持续高精度 GPS 搜星。采用“基站唤醒 + 运动传感器过滤 + 动态高精度打点”三级联动机制。
* 不触碰多媒体隐私，严格限制权限申请仅为：后台定位权限、健身记录/运动传感器权限。

#### 2. 状态机逻辑
1. **睡眠状态 (基站监控)**：App 在后台注册系统级重大位置变更监控 (`startMonitoringSignificantLocationChanges()`)。
2. **动态唤醒**：当用户移动超过几百米，iOS 系统唤醒 App。App 立即启动 `CMMotionActivityManager` 检查过去 5 分钟的运动状态。
3. **高精度打点**：若状态为 `walking`、`cycling` 或 `running`，则激活高精度定位（`CLLocationManager`）与气压计（`CMAltimeter`）。
4. **自动断开**：若检测到状态为 `stationary`（静止）持续超过 10 分钟，立刻停止高精度定位，退回到睡眠状态。

#### 3. 边界条件
* **跨日切分**：内存中维持当前写入的文件句柄。当本地时间触发 `00:00:00` 跨日，自动关闭昨日的 `YYYYMMDD.gpx` 文件流，异步更新其 `TripEntity` 统计信息，并初始化今日的新文件。
* **静止不动**：若全天无运动（步数变化 < 50 步且位置无 `Significant Change`），不生成任何 GPX 文件和 `TripEntity`。

---

### 模块 2：回忆剪贴簿（手动合并算法）

当用户在 UI 上勾选多个单日行程并点击“合并”时，Cursor 需实现以下原子操作：

**核心合并步骤（算法要求）：**
1. **读取阶段**：按照时间顺序读取被勾选的 $N$ 个 `.gpx` 文件。
2. **解析与拼接**：
    a. 保留第一个文件的 `<metadata>`。
    b. 提取每个文件中的 `<trkpt>` 节点。
    c. 在一个新的 `<trk>` 标签下，为每个独立文件保留各自的 `<trkseg>`（轨迹段），防止时间不连续导致连线错乱。
3. **重新计算统计量**：
    a. 重新累加所有点的距离：
    $$Distance = \sum Haversine(pt_i, pt_{i+1})$$
    b. 重新计算累计爬升（过滤噪点，海拔上升大于 2 米才计入累计）。
4. **文件写入与销毁**：
    a. 写入新文件 `Documents/Tracks/Merged_UUID.gpx`。
    b. 在 SwiftData 中创建一条新 `TripEntity`，`isMerged = true`。
    c. **隐藏策略**：将参与合并的原单日 `TripEntity` 的 UI 状态设为隐藏（或从 SwiftData 彻底删除，由用户在合并时二次确认）。

---

### 模块 3：临时探险队（免登录实时中转服务器）

#### 1. 客户端交互与生命周期
* **加入小队**：用户点击“加入/创建”，App 连接 WebSocket，发送 `join` 报文（包含 `roomID` 和临时 `nickname`）。
* **位置上报**：在队期间，由 `Tracking Engine` 产生的位置与气压计海拔数据，触发高频发送（3-5 秒一次）。
* **断开机制**：用户手动点击“退出”或领队点击“解散”，客户端发送 `leave` 报文并立刻强行 `close` 物理 socket 连接。

#### 2. 服务端通信协议 (WebSocket 极简 JSON)

**Action: 用户加入房间**
```json
// Client -> Server
{ "action": "join", "roomID": "889911", "nickname": "阿强" }
```

**Action: 位置广播 (高频)**
为了极致省电和省流，丢弃无用字段，只传递一维数组或紧凑型 JSON：
```json
// Client -> Server
{
  "action": "update",
  "roomID": "889911",
  "data": { "lon": -123.1207, "lat": 49.2827, "ele": 115.4 }
}

// Server -> Room Users (Broadcast)
{
  "event": "broadcast_update",
  "from": "阿强",
  "data": { "lon": -123.1207, "lat": 49.2827, "ele": 115.4, "timestamp": 1781359441 }
}
```

#### 3. 服务端纯内存管理逻辑 (Node.js 伪代码参考)
```typescript
interface User {
  ws: WebSocket;
  nickname: string;
  lastSeen: number;
}

// 内存字典, 无持久化数据库
const rooms = new Map<string, Map<string, User>>();

wss.on('connection', (ws) => {
  ws.on('message', (message) => {
    const parsed = JSON.parse(message.toString());

    if (parsed.action === 'join') {
      if (!rooms.has(parsed.roomID)) {
        rooms.set(parsed.roomID, new Map());
      }
      rooms.get(parsed.roomID)!.set(parsed.nickname, {
        ws, nickname: parsed.nickname, lastSeen: Date.now()
      });
    }

    if (parsed.action === 'update') {
      const room = rooms.get(parsed.roomID);
      if (room) {
        // 遍历转发给房间内除自己以外的所有人
        room.forEach((user, name) => {
          if (name !== parsed.nickname && user.ws.readyState === WebSocket.OPEN) {
            user.ws.send(JSON.stringify({
              event: 'broadcast_update',
              from: parsed.nickname,
              data: parsed.data
            }));
          }
        });
      }
    }
  });
});
```

---

## 四、 UI/UX 核心视图与交互提示

Cursor 在生成 SwiftUI 视图时，需严格遵循以下三个核心页面的布局：

### 1. 首页 (Timeline View)
* **顶部**：明显的“临时组队”入口按钮。
* **主体**：按月份分段的 List 视图，展示 `TripEntity`。
* **批量操作**：长按条目进入编辑模式，可勾选多行，底部弹出“打包合并为回忆”按钮。

### 2. 团队大盘 (Team Map & Elevation Split View)
* **上部分 (Map View)**：
    * 渲染所有队员的头像圆点（通过分配的 Hex 颜色区分）。
    * **弱网 UX 处理**：若某个队员的 `lastSeen` 超过 30 秒未更新，头像半透明；超过 3 分钟，头像变为灰色，且点击头像气泡显示 `[最后在线: X分钟前]`。
* **下部分 (Elevation Profile View)**：
    * 使用 SwiftUI Charts 绘制一条横向的海拔曲线图（X 轴为距离或相对时间，Y 轴为海拔高度）。
    * 在曲线上动态打点标记各团员当前高度。领队、掉队者之间的相对垂直高度落差必须一目了然。

---