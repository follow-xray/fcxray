# 参与贡献

欢迎通过 Issue 或 Pull Request 贡献。请避免提交真实节点、订阅令牌、密钥或签名证书。

1. 安装 README 中的工具链，执行 `flutter pub get` 与 `python3 tool/build.py bootstrap`。
2. 保持修改集中；涉及节点或路由时补充真实协议参数的测试，但使用保留域名或本机服务。
3. 提交前运行 `dart format lib test tool/config_fixtures.dart`、`python3 tool/build.py check` 与 `python3 tool/smoke.py`。
4. 原生平台改动需说明测试的 OS / SDK、架构和权限状态，区分编译通过与真实 TUN 转发通过。
5. 更新 Xray 时同时更新 `core.lock.json`、`native/go.mod`、`native/go.sum`，重新构建三个平台，不直接改动工作区中的上游仓库。

项目代码按 MPL-2.0 提交和分发。行为准则：友善、尊重事实、保护用户隐私。

界面改动提交前，检查新增和已有文案。操作用明确的按钮名表达；状态只显示一次。删掉副标题后若无法判断入口或下一步，先调整分组、位置和操作层级。参数细节放入现有的问号提示。
