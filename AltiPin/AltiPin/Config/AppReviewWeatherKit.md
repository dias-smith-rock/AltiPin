# App Review — WeatherKit Attribution (Guideline 5.2.5)

## Resolution Center reply (English)

Hello App Review Team,

TopoLog uses WeatherKit for current weather conditions displayed on the Compass tab, the Altitude tab Weather section, and the Geo Camera stamp overlay.

We have updated the app to meet Apple's WeatherKit attribution requirements:

- The official Apple Weather trademark is displayed via `WeatherService.attribution` (`combinedMarkDarkURL` / `combinedMarkLightURL`).
- A tappable "Weather Data Sources" link opens Apple's legal attribution page (`legalPageURL`).
- Attribution is shown only when data is served by WeatherKit (not when Open-Meteo fallback is used).

A screen recording on a physical device demonstrating these attribution elements is attached in App Review Information → Notes for this submission.

Thank you.

## 真机录屏检查清单

1. Compass Tab — 天气行下方可见  Weather 商标 +「天气数据来源」链接
2. Altitude Tab — 滚动到 Weather 区块，商标与链接可见；点击链接在 Safari 打开 Apple 法律页
3. Geo Camera — 预览区水印下方可见商标与链接；水印最后一行在 WeatherKit 数据下显示 "Weather"

## App Store Connect

- 路径：App → App Review Information → Notes
- 上传 30–60 秒真机录屏（非模拟器）
- 在 Resolution Center 回复中注明录屏已附于 Notes
