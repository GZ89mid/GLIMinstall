# GLIMinstall —— GLIM 依赖库源码快照镜像(私有仓库)

本仓库用于存放 [GLIM](https://github.com/koide3/glim) 一键安装脚本所需的第三方库与 ROS 包源码快照,解决两个问题:

1. **克隆稳定性**: GitHub 直连失败(HTTP2 framing 错误、443 超时)时,安装脚本会自动回退到本仓库下载固定版本快照,无需网络翻墙或反复重试。
2. **版本一致性**: 快照固定了相互兼容的版本组合(GTSAM 4.3a1 + gtsam_points/glim 最新 master),避免上游更新导致 API 不匹配编译失败。

## 内容

| 文件 | 说明 |
|---|---|
| `gtsam.tar.gz` | GTSAM 4.3a1 源码(含 137 个 PreintegratedImuMeasurementsT 符号所需的模板实例化) |
| `iridescence.tar.gz` | koide3/iridescence master(含全部 submodule) |
| `gtsam_points.tar.gz` | koide3/gtsam_points master(含 has_index 等新 API) |
| `glim.tar.gz` | koide3/glim master |
| `glim_ros2.tar.gz` | koide3/glim_ros2 master |
| `VERSIONS.txt` | 完整版本清单(上游 URL + 固定提交哈希) |

## 安装脚本如何回退

脚本 `GLIM一件安装脚本V1.0.sh` 中的 `retry_clone` 在 GitHub 克隆失败 3 次后,会通过 `gh api` 从本仓库下载 `<名字>.tar.gz` 并解压(以 `.glim_mirror` 标记),完全离线继续编译。

回退仓库可通过环境变量覆盖:

```bash
export GLIM_MIRROR_REPO="你的GitHub用户名/GLIMinstall"
```

## 离线手动使用

```bash
# 例如离线安装 gtsam 4.3a1
mkdir -p ~/lib/src/gtsam && tar -xzf gtsam.tar.gz -C ~/lib/src/gtsam --strip-components=1
cd ~/lib/src/gtsam && mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/lib/gtsam \
  -DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF -DGTSAM_BUILD_TESTS=OFF -DGTSAM_WITH_TBB=OFF \
  -DGTSAM_USE_SYSTEM_EIGEN=ON -DGTSAM_BUILD_WITH_MARCH_NATIVE=OFF \
  -DGTSAM_TANGENT_PREINTEGRATION=ON
make -j4 && make install
```
