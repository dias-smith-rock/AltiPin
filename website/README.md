# AltiPin 官网

AltiPin 产品静态官网，部署至 [compass.sryze.cc](https://compass.sryze.cc)。

## 目录结构

```
website/
├── index.html          # 首页
├── privacy/index.html  # 隐私政策 → /privacy/
├── terms/index.html    # 使用协议 → /terms/
├── css/styles.css
├── js/
│   ├── i18n.js         # 语言检测与切换
│   └── locales.js      # 8 语言翻译包
├── assets/favicon.svg
├── CNAME               # 自定义域名
└── robots.txt
```

## 多语言支持

| 语言代码 | 语言 |
|----------|------|
| `en` | English（**默认**） |
| `zh-Hans` | 简体中文 |
| `zh-Hant` | 繁體中文 |
| `es` | Español |
| `pt-BR` | Português (Brasil) |
| `ar` | العربية（RTL） |
| `hi` | हिन्दी |
| `fr` | Français |

**语言选择优先级：**

1. URL 参数 `?lang=zh-Hans`
2. 浏览器 `localStorage`（`altipin-lang`）
3. 浏览器系统语言
4. 回退到英语（`en`）

页面右上角有语言下拉菜单，切换后会写入 `localStorage` 并更新 URL。

**示例：**

- `https://compass.sryze.cc/?lang=zh-Hans`
- `https://compass.sryze.cc/privacy/?lang=fr`

**添加或修改翻译：** 编辑 [`js/locales.js`](js/locales.js) 中对应语言的对象，键名与 HTML 上的 `data-i18n` 属性一致。

## 本地预览

```bash
cd website
python3 -m http.server 8080
```

浏览器打开 [http://localhost:8080](http://localhost:8080)。

## 部署到 GitHub Pages

### 1. 提交并推送代码

```bash
cd /path/to/AltiPin   # 仓库根目录
git add website/ .github/workflows/deploy-website.yml AltiPin/AltiPin/Config/AppLinks.swift
git commit -m "Add product website for compass.sryze.cc"
git push origin main
```

### 2. 启用 GitHub Pages

1. 打开仓库 **Settings → Pages**
   - 地址：<https://github.com/dias-smith-rock/AltiPin/settings/pages>
2. **Build and deployment → Source** 选择 **GitHub Actions**（不要选 Deploy from a branch）
3. 推送代码后，在 **Actions** 标签页等待 **Deploy Website** 工作流完成（绿色 ✓）

首次部署成功后，站点可通过 `https://dias-smith-rock.github.io/AltiPin/` 访问（启用自定义域名后以自定义域名为准）。

### 3. 配置自定义域名

1. 仍在 **Settings → Pages → Custom domain** 填入：

   ```
   compass.sryze.cc
   ```

2. 点击 **Save**，等待 DNS 检查通过
3. 勾选 **Enforce HTTPS**（证书签发可能需要数分钟至 24 小时）
4. 确认 `website/CNAME` 文件内容为 `compass.sryze.cc`（已包含，每次 Actions 部署会自动带上）

### 4. 配置 DNS

在 `sryze.cc` 的域名服务商（如 Cloudflare）添加记录：

| 类型  | 名称      | 值                          | 说明        |
|-------|-----------|-----------------------------|-------------|
| CNAME | `compass` | `dias-smith-rock.github.io` | 指向 GitHub |

**Cloudflare 用户建议**：首次配置时先将代理设为 **DNS only（灰云）**，待 GitHub 成功签发 HTTPS 证书后再决定是否开启 CDN 代理。

验证 DNS：

```bash
dig compass.sryze.cc CNAME +short
# 期望输出：dias-smith-rock.github.io.
```

### 5. 验证清单

- [ ] `https://compass.sryze.cc/` — 首页正常
- [ ] `https://compass.sryze.cc/privacy/` — 隐私政策
- [ ] `https://compass.sryze.cc/terms/` — 使用协议
- [ ] HTTPS 证书有效（浏览器地址栏无警告）
- [ ] iOS App 设置页「隐私」「使用协议」「访问官网」跳转正确

## 更新网站

修改 `website/` 下任意文件后 push 到 `main` 分支，GitHub Actions 会自动重新部署，通常 1–2 分钟内生效。

手动触发部署：仓库 **Actions → Deploy Website → Run workflow**。

## 相关链接

- GitHub 仓库：<https://github.com/dias-smith-rock/AltiPin>
- 联系邮箱：music.player.250617@gmail.com
