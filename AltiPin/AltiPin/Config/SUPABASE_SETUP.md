# Supabase Realtime 接入说明

## 1. 创建项目

1. 登录 [supabase.com](https://supabase.com) → **New Project**
2. 打开 **Project Settings → API**，记录：
   - **Project URL**：`https://<ref>.supabase.co`
   - **anon public key**（legacy JWT 或 publishable key）

**重要：** URL 中的 `<ref>` 必须与 anon key 对应。可在 [jwt.io](https://jwt.io) 解码 JWT，确认 `ref` 字段与 URL 一致。

例如 URL 为 `...mcng.supabase.co`，JWT 中 `ref` 也必须是 `...mcng`，不能是 `...mcnq`。

## 2. 启用 Realtime

**Project Settings → Realtime** 中确认 **Broadcast**、**Presence** 已开启（默认已开）。

本轮无需数据库业务表或 Postgres Changes。

## 3. 配置 Realtime 授权（必做）

新版 Supabase 默认开启 **Realtime Authorization**。未配置策略时，客户端无法加入频道，Inspector 会一直空白。

### 方案 A（推荐）：执行 SQL 策略

1. 打开 **SQL Editor**
2. 粘贴并运行 [`supabase_realtime_policies.sql`](supabase_realtime_policies.sql)
3. 该脚本允许 `anon` 角色使用 `team:*` 频道的 Broadcast 与 Presence

### 方案 B：开启公共访问

**Realtime → Settings** 中开启 **Allow public access**（若你的项目有此选项）。

仍建议执行方案 A，限制仅 `team:*` 话题可访问。

## 4. 配置客户端

```bash
cp AltiPin/Config/Secrets.example.xcconfig AltiPin/Config/Secrets.xcconfig
```

编辑 `Secrets.xcconfig`：

```xcconfig
SUPABASE_PROJECT_REF = yksdkcuekvwxrlygmcng
SUPABASE_ANON_KEY = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**注意：** 不要写 `https://` 完整 URL。xcconfig 会把 `//` 当成注释，即使加引号也会截断为 `https:`。  
只填 Dashboard 上 Project URL 的中间那段 ref（如 `https://<ref>.supabase.co` 里的 `<ref>`）。

修改后 **Clean Build Folder** 再运行。

## 5. 频道约定

- Topic：`team:<roomID>`（如 `team:4829`）
- Public channel（`isPrivate = false`）
- 位置：`broadcast_update` 事件
- 在线成员：Presence `track` / `presenceChange`

## 6. 验证

### Dashboard Inspector

1. 打开 **Realtime → Inspector**
2. 在 **Join a channel** 输入：`team:4829`
3. 点击 **Start listening**
4. 运行 App 并创建队伍；Inspector 应出现 presence / broadcast 消息

若 Inspector 始终空白，说明授权策略未生效或 URL/key 项目不匹配。

### 双端联调

两台设备输入相同 4 位房间码，应能看到对方在线与轨迹更新。

## 7. 常见错误

| 现象 | 原因 | 处理 |
|------|------|------|
| 创建队伍失败 | URL 被 xcconfig 截断为 `https:` | URL 加双引号 |
| Inspector 空白 | 未配置 Realtime 授权策略 | 执行 SQL 脚本 |
| 连接失败 | URL 与 anon key 不是同一项目 | 核对 JWT 中 `ref` |
| 订阅超时 | 未先连接 WebSocket | 已在客户端修复 |
