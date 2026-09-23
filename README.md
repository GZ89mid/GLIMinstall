# GLIMinstall —— GLIM 一键安装脚本与依赖库源码快照(私有镜像仓库)

本仓库提供 [GLIM](https://github.com/koide3/glim) 的**一键安装脚本**(镜像优先版)与**固定版本依赖库源码快照**,解决两个问题:

1. **克隆稳定性**: GitHub 直连失败(HTTP2 framing 错误、443 超时)时,安装脚本会自动回退到本仓库下载固定版本快照,无需网络翻墙或反复重试。
2. **版本一致性**: 快照固定了相互兼容的版本组合(GTSAM 4.3a1 + gtsam_points/glim 最新 master),避免上游更新导致 API 不匹配编译失败。

## 快速安装

```bash
# 1. 下载一键安装脚本(镜像优先版 V1.6)
wget https://raw.githubusercontent.com/GZ89mid/GLIMinstall/main/GLIM_install_static.sh
# 或: curl -L -O https://raw.githubusercontent.com/GZ89mid/GLIMinstall/main/GLIM_install_static.sh

# 2. 赋予执行权限并运行
chmod +x GLIM_install_static.sh
./GLIM_install_static.sh
```

运行后按提示选择第三方库清理模式:

- **1** —— 全盘清理重装(删除安装目录与源码后重新克隆编译)
- **2** —— 仅清 build 缓存与安装目录(保留源码,推荐)
- **3** —— 复用现有安装(库完整时跳过编译,最快)

脚本自动完成: CPU/GPU 与 CUDA 版本选择、ROS2 发行版检测、GTSAM/iridescence/gtsam_points 三库并行编译、glim/glim_ros 工作区编译、旧版残留清理(~/lib、/usr/local 与 /opt/ros/humble 中的旧 GTSAM/glim)、GUI 环境验证(有显示环境时自动试启动 offline_viewer)。

## 内容

| 文件 | 说明 |
|---|---|
| `GLIM_install_static.sh` | 一键安装脚本 V1.6(镜像优先版: 克隆失败时自动回退本仓库快照,支持 CPU/GPU、并行编译、旧残留清理、GUI 验证) |
| `gtsam.tar.gz` | GTSAM 4.3a1 源码(含 137 个 PreintegratedImuMeasurementsT 符号所需的模板实例化) |
| `iridescence.tar.gz` | koide3/iridescence master(含全部 submodule) |
| `gtsam_points.tar.gz` | koide3/gtsam_points master(含 has_index 等新 API) |
| `glim.tar.gz` | koide3/glim master |
| `glim_ros2.tar.gz` | koide3/glim_ros2 master |
| `VERSIONS.txt` | 完整版本清单(上游 URL + 固定提交哈希) |

## 安装脚本如何回退

脚本 `GLIM_install_static.sh` 中的 `retry_clone` 在 GitHub 克隆失败 3 次后,会通过 `gh api` 从本仓库下载 `<名字>.tar.gz` 并解压(以 `.glim_mirror` 标记),完全离线继续编译。

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
