# Supabase Realtime 接入说明

## 1. 创建项目

1. 登录 [supabase.com](https://supabase.com) → **New Project**
2. 打开 **Project Settings → API**，记录：
   - **Project URL**：`https://<ref>.supabase.co`
   - **anon public key**

## 2. 启用 Realtime

**Project Settings → Realtime** 中确认 **Broadcast**、**Presence** 已开启（默认已开）。

本轮无需数据库表或 Postgres Changes。

## 3. 配置客户端

```bash
cp AltiPin/Config/Secrets.example.xcconfig AltiPin/Config/Secrets.xcconfig
```

编辑 `Secrets.xcconfig`，填入 URL 与 anon key，重新编译即可。

## 4. 频道约定

- Topic：`team:<roomID>`（如 `team:4829`）
- Public channel，仅 anon key，无需登录
- 位置：`broadcast_update` 事件
- 在线成员：Presence `track` / `presenceChange`

## 5. 验证

Dashboard → **Realtime → Inspector**，向 topic `team:0001` 发送测试 broadcast，确认项目 Realtime 正常。

双端使用相同 4 位房间码入队，应能看到对方在线与轨迹更新。
