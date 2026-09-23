#!/usr/bin/env bash
set -euo pipefail

# =========================
# GLIM One-Click Installer (Interactive) V1.6 私有仓库镜像版
# - choose CPU/GPU via input 1/2
# - GPU -> choose CUDA version (12.2 / 12.6 / 13.1)
# - auto-detect ROS2 distro (humble/jazzy) & Ubuntu version (22.04/24.04)
# - auto-install base tools (git, curl, gpg, cmake, make) on any x86 machine
# - CUDA 12.2 restricted to Ubuntu 22.04 only (matches official PPA)
# - NVIDIA driver PPA auto-added (ppa:graphics-drivers)
# - verify CUDA-driver compatibility (CUDA 12.2→535, 12.6→560, 13.1→590)
# - install 3rd-party libs into ~/lib/<name>
# - ROS2 workspace path configurable
# - auto source ROS2 setup.bash before colcon build
# Changelog V0.5→V0.6:
#   - [修复] detect_ros2_distro() 不再因缺少 /opt/ros/<distro>/setup.bash 直接退出。
#     全新机器会标记 ROS2_INSTALL_NEEDED，在系统依赖阶段自动安装 ROS2（含 apt 源配置）
#   - [修复] install_nvidia_driver_for_cuda() 在 nvidia-smi 无法通信(取不到版本)时，
#     改用 dpkg 查询已安装驱动版本，避免把高版本驱动(如 595)误降级为 535；
#     已装驱动 >= 目标版本时直接跳过；对 RTX 50 系列(Blackwell, 需 >=570)给出降级警告
#   - [修复] verify_cuda_driver_compat() 在 nvidia-smi 不可用时回退到 dpkg 检测版本
#   - [修复] detect_cuda() 在 nvcc 不在 PATH 时搜索 /usr/local/cuda-* 等常见路径；
#     cuda.h 中的 CUDA_VERSION(如 12020) 正确解析为 12.2
#   - [修复] ensure_cuda_symlink_and_env() 优先用 update-alternatives 管理 /usr/local/cuda
#   - [修复] 移除驱动安装后的"立即重启"提示（避免脚本中途重启导致安装中断）
#   - [改进] ask_path() 支持 ~ 路径展开；内存 <24GiB 时自动降低编译并行数防 OOM
# Changelog V0.9→V1.0:
#   - [修复] GTSAM 版本 4.3a0 → 4.3a1。4.3a0 缺少 PreintegratedImuMeasurementsT
#     模板类及显式实例化（gtsam_points/glim 官方 CI 使用 4.3a1），
#     导致 glim_ros 链接时报 undefined reference to PreintegratedImuMeasurementsT
#   - [修复] GTSAM / gtsam_points 编译前删除旧 build 目录，避免陈旧 CMakeCache
#     （如 GTSAM_DIR 指向 /usr/local）和陈旧对象文件造成版本混编
#   - [修复] gtsam_points 与 colcon 构建时显式传入 -DGTSAM_DIR=$LIB_ROOT/gtsam/lib/cmake/GTSAM，
#     杜绝误用 /usr/local 残留的 GTSAM
#   - [修复] 删除 /usr/local 中残留的旧 GTSAM（旧版脚本/手动安装），消除版本冲突
# Changelog V1.0→V1.1:
#   - [新增] 每次启动时可选择清理 ~/lib 中残留的第三方库(GTSAM/gtsam_points/iridescence):
#       1=全部清理重装(删安装+源码) 2=仅清 build 缓存与安装目录(保留源码,推荐) 3=复用现有安装跳过编译
#   - [修复] iridescence 编译前同样删除陈旧 build 目录(与 GTSAM/gtsam_points 保持一致)
#   - [修复] 第三方库重新编译后自动清除 glim/glim_ros 的 colcon 构建缓存，强制重新链接，防止混链
#   - [改进] 安装后自动检查 GUI 运行环境(显示环境/OpenGL/GLFW/iridescence)；
#     verify_install 按是否有显示环境自动选择 GUI 启动验证或无头验证
#   - [改进] 安装完成后可选立即启动 rviz2 / offline_viewer 图形化界面
# Changelog V1.3→V1.4(私有仓库镜像版):
#   - 优先从私有镜像仓库 GZ89mid/GLIMinstall 下载固定版本源码快照(保证版本一致)
#   - GitHub 直连仅作为镜像不可用时的回退通道
# Changelog V1.4→V1.6:
#   - [修复] retry_clone 参数顺序(选项必须放在 URL/目录之后)；镜像下载改 raw 请求头(修复 1MB 限制)
#   - [修复] colcon build 增加 --base-paths src，避免工作区其他目录触发重复包名错误
#   - [修复] run_as_owner 中的 export LD_LIBRARY_PATH 改为外层转义双引号(\")包裹且 $LD_LIBRARY_PATH 转义为 \$LD_LIBRARY_PATH(5 处)：既防外层提前展开成终端值覆盖 source 注入的库路径，又防单引号阻止内层展开导致字面量 \$LD_LIBRARY_PATH 污染，确保工作区/ROS 库路径保留(修复 undefined symbol 与 librcl_action.so 导入失败)
#   - [修复] 新增清理 /opt/ros/humble 中旧版脚本残留的 glim/glim_ros 库与配置，消除动态库/CMake 版本冲突
#   - [优化] 三个库源码并行克隆；GTSAM 与 iridescence 并行编译；输出加行前缀并写日志，失败自动汇总
# =========================

welcome() {
  local delay=0.02
  while IFS= read -r line; do
    echo "$line"
    sleep "$delay"
  done <<'BANNER'
                              O0O              o00
                              0@0              o@@
                              0@0              o@@
                              0@0              o@@
                              0@0              o@@
                              0@0              o@@
                      oo      0@0              o@@      oOo
                    O@@@@   o 0@0oOOOOOOOOOOOOoo@@ o   0@@@0
                    O@@@@o000o0@0O0000000000000o@@ 000o0@@@@
                    O@@@@o0@@o0@0O@@@@@@@@@@@@@o@@ @@0o0@@@@
                 oOOO@@@@o@@@o0@0O@@@@@@@@@@@@@o@@ @@@o0@@@@oOOo
                O@@OO@@@@o@@@o0@0O@@@@@@@@@@@@@o@@ @@@o0@@@@o@@0
                O@@OO@@@@o@@@o0@0O@@@@@@@@@@@@@o@@ @@@o0@@@@o@@0
       ooo      O@@OO@@@@o@@@o0@0oO00000000000OO@@ @@@o0@@@@o@@0       oo
         oOO oOOO@@OO@@@@o000o0@@@0ooooooooooO@@@@ 000o0@@@@o@@0oOO oOO
           oO00OO@@OO@@@@oooo 0@@@@          0@@@@  ooo0@@@@o@@0oO00o
              O@0O0OO@@@@o    0@@@@          0@@@@     0@@@@o0OO00o
                O@@0OO@@@oo   0@@@@          0@@@@   o 0@@0OO0@0o
                  o0@@0O0o@0Oo0@@@@          0@@@@ O0@oOOO0@@Oo
                    oO@@@OO0@O0@@@@          0@@@@o@0OO0@@0o
                       O0@@0OoO@@@@          0@@@0oO0@@@Oo
                         oO@@@0OO0@ 0O    o0o0@OO0@@@0o
                            o0@@@0Oo0@@0O@@@oO0@@@@Oo
                              oO@@@@0OO0@0OO@@@@0o
                                 o0@@@@0O0@@@@Oo
                                   oO@@@@@@0o
                                      o00Oo
                                        o
--------------------------------------------------------------------------------
--oOOOOOOo------oOO0OOo-----OOOOOOo------oOO00OOo---OOOOOOOOOO--OO-----OO00OO---
--O@O---o0@o--O@0o---o0@O---0@o--o@@o--o@0Oo--oO@0o--ooo@@oooo--@@---O@0o--o0@o-
--O@O----0@O-O@0-------0@O--0@o--o@0---@@-------O@0-----@@------@@--o@@---------
--O@00000Oo--0@O-------O@O--0@0OO00Oo-o@@-------o@@-----@@------@@--o@0---------
--O@O--0@O---o@0-------0@o--0@o---o@@--@@o------O@0-----@@------@@---@@o-----o--
--O@O---O@0---o00OoooO00o---0@OooO0@O---0@0OooO0@O------@@------@@---o0@OooO00o-
--ooo----ooo----ooOOOo------ooooooo-------ooOOoo--------oo------oo-----ooOOoo---
--------------------------------------------------------------------------------
BANNER
  echo "欢迎使用华工国际RobotIC实验室GLIM 一键安装 V1.1"
  echo "----------------------------------------"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "[ERROR] 缺少命令: $1"; exit 1; }
}

# 自动安装所有 x86 机器必需的基础工具
auto_install_base_tools() {
  log "检查并安装基础工具 (git, curl, gpg, wget, cmake, make, build-essential)..."
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "当前系统不支持 apt，请手动安装 git, curl, cmake, make。"
    return 1
  fi

  local missing=""
  for cmd in git curl gpg wget cmake make; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing="$missing $cmd"
    fi
  done

  if [[ -n "$missing" ]]; then
    log "安装缺失的工具:$missing"
    sudo apt update -qq
    sudo apt install -y git curl gpg wget cmake make build-essential pkg-config software-properties-common
  else
    log "基础工具已就绪 ✓"
  fi
  return 0
}

# 检测 Ubuntu 版本
detect_ubuntu_version() {
  UBUNTU_VERSION="$(lsb_release -rs 2>/dev/null || echo '')"
  UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || echo '')"
  if [[ -z "$UBUNTU_VERSION" ]]; then
    # Fallback: read from os-release
    UBUNTU_VERSION="$(grep -oP 'VERSION_ID="?\K[0-9]+\.[0-9]+' /etc/os-release 2>/dev/null || echo '')"
  fi
  if [[ -z "$UBUNTU_VERSION" ]]; then
    err "无法检测 Ubuntu 版本。此脚本仅支持 Ubuntu 22.04 / 24.04。"
    exit 1
  fi
  log "检测到 Ubuntu $UBUNTU_VERSION ($UBUNTU_CODENAME)"
}

# 校验 CUDA 版本是否与当前 Ubuntu 版本兼容 (CUDA 12.2 仅限 22.04)
validate_cuda_ubuntu_compat() {
  local cuda_ver="$1"
  case "$UBUNTU_VERSION" in
    22.04)
      # 22.04 支持 12.2, 12.6, 13.1 — 全部通过
      log "Ubuntu 22.04 + CUDA $cuda_ver: 兼容 ✓"
      return 0
      ;;
    24.04)
      # 24.04 不支持 CUDA 12.2
      if [[ "$cuda_ver" == "12.2" ]]; then
        err "CUDA 12.2 仅支持 Ubuntu 22.04 (ROS2 Humble)，不支持 Ubuntu 24.04。"
        echo "Ubuntu 24.04 请选择 CUDA 12.6 或 13.1。"
        return 1
      fi
      log "Ubuntu 24.04 + CUDA $cuda_ver: 兼容 ✓"
      return 0
      ;;
    *)
      warn "未知 Ubuntu 版本 $UBUNTU_VERSION，跳过 CUDA 兼容性检查。"
      return 0
      ;;
  esac
}

# 自动检测 ROS2 发行版（humble / jazzy 等）
# V0.6: 若本机尚未安装 ROS2，不再直接退出（原逻辑在全新机器上会因找不到
# setup.bash 而 return 1，配合 set -e 直接终止脚本，导致后面安装 ros-base 的步骤永远执行不到），
# 改为标记 ROS2_INSTALL_NEEDED=1，由系统依赖阶段自动安装。
detect_ros2_distro() {
  ROS2_DISTRO=""
  ROS2_INSTALL_NEEDED=0
  local name ros_opt="${ROS2_OPT_DIR:-/opt/ros}"
  # 方法1：检查 /opt/ros/ 下的目录
  if [[ -d "$ros_opt" ]]; then
    for d in "$ros_opt"/*/; do
      name="$(basename "$d")"
      if [[ -f "$d/setup.bash" && "$name" != "rosdep" ]]; then
        ROS2_DISTRO="$name"
        break
      fi
    done
  fi
  # 方法2：检查 apt 安装的 ros-<distro>-desktop
  if [[ -z "$ROS2_DISTRO" ]]; then
    ROS2_DISTRO="$(dpkg -l 2>/dev/null | grep -oP 'ros-(humble|jazzy|iron|rolling)-desktop' | head -1 | sed 's/ros-//;s/-desktop//')"
  fi
  if [[ -z "$ROS2_DISTRO" ]]; then
    case "$UBUNTU_VERSION" in
      24.04) ROS2_DISTRO="jazzy" ;;
      *)     ROS2_DISTRO="humble" ;;
    esac
    log "未检测到已安装的 ROS2，根据 Ubuntu 版本推断发行版: $ROS2_DISTRO"
  else
    log "检测到 ROS2 发行版: $ROS2_DISTRO"
  fi
  ROS2_SETUP="$ros_opt/$ROS2_DISTRO/setup.bash"
  if [[ ! -f "$ROS2_SETUP" ]]; then
    ROS2_INSTALL_NEEDED=1
    warn "未找到 $ROS2_SETUP，将在系统依赖步骤中自动安装 ROS2 $ROS2_DISTRO（首次安装需配置 ROS2 apt 源）。"
  else
    ROS2_INSTALL_NEEDED=0
  fi
  return 0
}

# 配置 ROS2 apt 源（仅首次安装 ROS2 时需要；已装 ROS2 的机器直接跳过）
setup_ros2_repo() {
  [[ "${ROS2_INSTALL_NEEDED:-0}" -eq 0 ]] && return 0
  local codename="${UBUNTU_CODENAME:-$(lsb_release -cs 2>/dev/null || echo focal)}"
  log "配置 ROS2 $ROS2_DISTRO apt 源 (Ubuntu $codename)..."
  sudo apt update -qq
  sudo apt install -y curl gnupg lsb-release
  sudo mkdir -p /usr/share/keyrings
  if ! sudo curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg; then
    sudo wget -qO /usr/share/keyrings/ros-archive-keyring.gpg https://raw.githubusercontent.com/ros/rosdistro/master/ros.key
  fi
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $codename main" | sudo tee /etc/apt/sources.list.d/ros2.list >/dev/null
  sudo apt update -qq
}

# 检测系统中的 CUDA（可选），设置 CUDA_AVAILABLE 与 CUDA_VERSION
# V0.6: nvcc 不在 PATH 时也会在 /usr/local/cuda* 等常见路径中查找；
# cuda.h 中的 CUDA_VERSION(如 12020) 会正确解析为 12.2
detect_cuda() {
  CUDA_AVAILABLE=0
  CUDA_VERSION=""
  local nvcc_path="" d v
  if command -v nvcc >/dev/null 2>&1; then
    nvcc_path="$(command -v nvcc)"
  else
    for d in ${CUDA_SEARCH_DIRS:-/usr/local/cuda /usr/local/cuda-* /usr/lib/cuda}; do
      if [[ -x "$d/bin/nvcc" ]]; then
        nvcc_path="$d/bin/nvcc"
        break
      fi
    done
  fi

  if [[ -n "$nvcc_path" ]]; then
    CUDA_AVAILABLE=1
    CUDA_VERSION="$("$nvcc_path" --version | sed -n 's/.*release \([0-9]\+\.[0-9]\+\).*/\1/p')"
  else
    # Fallback: check common headers
    if [[ -f "/usr/local/cuda/include/cuda.h" ]] || [[ -f "/usr/include/cuda.h" ]]; then
      CUDA_AVAILABLE=1
      v="$(grep -m1 -E '#define CUDA_VERSION' /usr/local/cuda/include/cuda.h 2>/dev/null | awk '{print $3}')"
      if [[ "$v" =~ ^[0-9]{5}$ ]]; then
        # cuda.h 中的格式为 12020 -> 12.2
        CUDA_VERSION="$((10#${v:0:2})).$((10#${v:2:2}))"
      fi
    fi
  fi

  if [[ "$CUDA_AVAILABLE" -eq 1 ]]; then
    if [[ -z "$CUDA_VERSION" ]]; then
      log "检测到 CUDA 工具链，但未能解析版本号。"
    else
      log "检测到 CUDA 版本: $CUDA_VERSION"
    fi
  else
    log "未检测到 CUDA 工具链 (nvcc 或 cuda headers)。CUDA 将不可用。"
  fi
}

# 获取已安装 NVIDIA 驱动的版本号
# V0.6: nvidia-smi 无法通信(取不到版本)时，回退到 dpkg 查询已安装的 nvidia-driver-* 包
get_installed_driver_version() {
  local ver=""
  if command -v nvidia-smi >/dev/null 2>&1; then
    ver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || true)"
  fi
  if [[ -z "$ver" ]] && command -v dpkg-query >/dev/null 2>&1; then
    ver="$(dpkg-query -W -f='${Version}\n' 'nvidia-driver-*' 2>/dev/null | grep -oP '^\d+' | sort -rn | head -1 || true)"
  fi
  echo "$ver"
}

# 验证 CUDA 版本与 NVIDIA 驱动之间的兼容性
# 参考: https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html
verify_cuda_driver_compat() {
  local cuda_ver="$1"
  local min_driver
  case "$cuda_ver" in
    12.2) min_driver=535 ;;
    12.6) min_driver=560 ;;
    13.1) min_driver=590 ;;
    *)    min_driver=535 ;;
  esac

  local inst_drv
  inst_drv="$(get_installed_driver_version)"
  if [[ -z "$inst_drv" ]]; then
    warn "无法确定已安装的 NVIDIA 驱动版本，无法验证兼容性。请确保已安装 >= ${min_driver}.xx 的驱动。"
    return 2
  fi

  local inst_major
  inst_major="${inst_drv%%.*}"
  log "检测到 NVIDIA 驱动版本: $inst_drv, CUDA $cuda_ver 最低要求: ${min_driver}.xx"

  if [[ "$inst_major" =~ ^[0-9]+$ ]] && (( inst_major >= min_driver )); then
    log "驱动版本兼容 ✓"
    return 0
  else
    err "驱动版本不兼容！当前驱动 $inst_drv < 最低要求 ${min_driver}.xx。"
    echo "CUDA $cuda_ver 需要 NVIDIA 驱动 >= ${min_driver}.xx。"
    echo "请先升级驱动后重试，或选择其他 CUDA 版本。"
    return 1
  fi
}

# 新增函数：通过 NVIDIA 官方仓库自动安装 CUDA Toolkit
install_cuda_toolkit() {
  # $1 = version like 12.2 or 12.6 or 13.1
  local ver="$1"
  log "通过 NVIDIA 官方仓库安装 CUDA Toolkit $ver"

  if ! command -v apt-get >/dev/null 2>&1; then
    warn "当前系统不支持 apt 自动安装。请手动安装 CUDA $ver： https://developer.nvidia.com/cuda-toolkit-archive"
    return 2
  fi

  local major="${ver%%.*}"
  local minor="${ver#*.}"
  # NVIDIA 官方包名格式: cuda-toolkit-12-2
  local nvidia_pkg="cuda-toolkit-${major}-${minor}"

  # 根据 Ubuntu 版本确定 keyring 下载地址
  local ubuntu_codename
  case "$UBUNTU_VERSION" in
    22.04) ubuntu_codename="ubuntu2204" ;;
    24.04) ubuntu_codename="ubuntu2404" ;;
    *)     ubuntu_codename="ubuntu2204" ;;
  esac

  local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${ubuntu_codename}/x86_64/cuda-keyring_1.1-1_all.deb"
  local keyring_deb="/tmp/cuda-keyring_$$.deb"

  # 步骤1: 安装 cuda-keyring（幂等，已安装则跳过）
  if dpkg -l cuda-keyring 2>/dev/null | grep -q '^ii'; then
    log "cuda-keyring 已安装，跳过。"
  else
    log "下载并安装 NVIDIA cuda-keyring..."
    if ! wget -q --show-progress -O "$keyring_deb" "$keyring_url"; then
      warn "下载 cuda-keyring 失败，尝试使用 curl..."
      if ! curl -fsSL -o "$keyring_deb" "$keyring_url"; then
        err "无法下载 cuda-keyring。请检查网络连接或手动安装 CUDA。"
        echo "手动安装步骤: https://developer.nvidia.com/cuda-downloads"
        rm -f "$keyring_deb"
        return 3
      fi
    fi
    sudo dpkg -i "$keyring_deb" || {
      err "cuda-keyring 安装失败。"
      rm -f "$keyring_deb"
      return 1
    }
    rm -f "$keyring_deb"
    log "cuda-keyring 安装成功。"
  fi

  # 步骤2: apt update
  sudo apt update -qq

  # 步骤3: 安装指定版本的 CUDA Toolkit
  if apt-cache show "$nvidia_pkg" >/dev/null 2>&1; then
    log "发现 NVIDIA 官方包 '$nvidia_pkg'，正在安装..."
    if sudo apt install -y "$nvidia_pkg"; then
      log "CUDA Toolkit $ver 安装完成。"
      return 0
    else
      err "安装 $nvidia_pkg 失败。请检查 apt 源或手动安装。"
      return 1
    fi
  else
    # 备选方案：尝试安装 nvidia-cuda-toolkit（Ubuntu 默认源中的版本，可能较旧）
    warn "未找到 '$nvidia_pkg'，尝试安装 Ubuntu 默认源中的 nvidia-cuda-toolkit..."
    if apt-cache show nvidia-cuda-toolkit >/dev/null 2>&1; then
      log "安装 nvidia-cuda-toolkit（版本可能与 $ver 不同）..."
      if sudo apt install -y nvidia-cuda-toolkit; then
        warn "已安装 nvidia-cuda-toolkit（来自 Ubuntu 默认源），版本可能与 $ver 不同。"
        return 0
      fi
    fi
    err "无法找到 CUDA Toolkit 软件包。请手动安装: https://developer.nvidia.com/cuda-downloads"
    return 3
  fi
}

# 新版：根据所选 CUDA 安装指定驱动（12.2->535,12.6->560,13.1->590）
# V0.6 修复：
#  - 原逻辑只有在 nvidia-smi 能返回版本时才询问"是否降级"，而 nvidia-smi 无法通信
#    （本机当前状态）时会绕过询问直接降级安装目标驱动，可能把新驱动(595)降成旧版(535)，
#    而 RTX 50 系列(Blackwell)显卡需要驱动 >= 570，降级会导致显卡无法使用。
#    现在统一通过 dpkg 获取已安装驱动版本：已装驱动 >= 目标版本时直接跳过；
#    需要降级时仍会先征询用户同意。
#  - 移除"安装后立即重启"提示（中途重启会导致整个安装中断，改为脚本结束后提醒）。
install_nvidia_driver_for_cuda() {
  # $1 = CUDA version string like 12.2
  local cuda_ver="$1"
  log "尝试为 CUDA $cuda_ver 安装/更新 NVIDIA 驱动（通过 apt 安装指定版本，必要时可降级）"

  need_cmd sudo
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "当前系统不支持 apt 自动安装 NVIDIA 驱动，请手动安装。"
    return 2
  fi

  local target_drv
  case "$cuda_ver" in
    12.2) target_drv=535 ;;
    12.6) target_drv=560 ;;
    13.1) target_drv=590 ;;
    *) target_drv=535 ;;
  esac

  # 先确定当前已安装的驱动版本（不依赖 nvidia-smi 是否可用）
  local inst_ver
  inst_ver="$(get_installed_driver_version)"
  if [[ -n "$inst_ver" ]]; then
    local inst_major
    inst_major="${inst_ver%%.*}"
    if [[ "$inst_major" =~ ^[0-9]+$ ]] && (( inst_major >= target_drv )); then
      log "已安装驱动 ${inst_ver} >= 目标 ${target_drv}.xx，无需安装，跳过。"
      return 0
    fi

    warn "检测到已安装驱动 ${inst_ver}，目标驱动为 ${target_drv}。"
    if (( target_drv < 570 )); then
      echo "  ⚠ 注意：RTX 50 系列 (Blackwell) 显卡需要驱动 >= 570，降级到 ${target_drv} 会导致显卡无法使用！"
    fi
    echo "是否强制安装目标驱动 nvidia-driver-${target_drv}（会降级替换已安装驱动）?"
    echo "  1) 是，强制安装目标驱动（通过 apt）"
    echo "  2) 否，保留当前驱动并跳过此步骤"
    local force_choice
    force_choice="$(ask_choice "请输入 1 或 2: " 1 2)"
    if [[ "$force_choice" != "1" ]]; then
      log "用户选择保留当前驱动 ${inst_ver}，跳过安装。"
      return 0
    fi
  fi

  # Attempt to install the target driver package via apt, allowing downgrades
  log "添加 NVIDIA 官方 PPA 以获得最新驱动..."
  sudo add-apt-repository -y ppa:graphics-drivers/ppa 2>/dev/null || true
  sudo apt update -qq

  local pkg="nvidia-driver-${target_drv}"
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    log "发现驱动包 $pkg，正在通过 apt 安装（允许降级）..."
    if ! sudo apt install -y --allow-downgrades "$pkg"; then
      warn "通过 apt 直接安装 $pkg 失败，尝试移除可能冲突的 nvidia 包后重试。"
      # Try removing common conflicting packages and retry
      sudo apt remove -y 'nvidia-*' 'libnvidia-*' || true
      sudo apt autoremove -y || true
      if ! sudo apt install -y --allow-downgrades "$pkg"; then
        err "无法通过 apt 安装 $pkg。请检查 apt 源或手动安装所需驱动。"
        return 1
      fi
    fi
  else
    err "apt 源中未找到驱动包 $pkg。请启用包含该驱动的仓库或手动下载安装。"
    echo "可参考： https://www.nvidia.com/Download/index.aspx 或 使用 'Software & Updates' -> Additional Drivers 添加官方驱动源。"
    return 3
  fi

  sudo depmod -a || true

  # 检查 nvidia-smi 是否可用（无需 sudo）
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    log "驱动安装完成并可用（nvidia-smi 可运行）。"
  else
    warn "驱动安装完成，但 nvidia-smi 当前不可用。通常需要重启以加载内核模块并完成安装。"
    echo "建议：等本脚本全部执行完毕后，再手动重启系统（sudo reboot），然后运行 nvidia-smi 确认。"
  fi

  return 0
}

# 确保 /usr/local/cuda 指向已安装的 CUDA 并在当前脚本环境导出必要变量
ensure_cuda_symlink_and_env() {
  # $1 = desired version like 12.2
  local ver="$1"
  local major="${ver%%.*}"
  local found=""

  # 优先搜索 /usr/local/cuda-XX 目录（测试可用 CUDA_SEARCH_DIRS 覆盖搜索路径）
  # 第一遍: 精确匹配目标版本（如 12.2），避免命中 cuda-12 这类 alternatives 链接
  for d in ${CUDA_SEARCH_DIRS:-/usr/local/cuda-* /usr/local/cuda*}; do
    if [[ -d "$d" && -x "$d/bin/nvcc" && "$d" == *"$ver"* ]]; then
      found="$d"
      break
    fi
  done
  # 第二遍: 仅匹配大版本号（如 12）
  if [[ -z "$found" ]]; then
    for d in ${CUDA_SEARCH_DIRS:-/usr/local/cuda-* /usr/local/cuda*}; do
      if [[ -d "$d" && -x "$d/bin/nvcc" && "$d" == *"$major"* ]]; then
        found="$d"
        break
      fi
    done
  fi
  # 第三遍: 任意可用 CUDA 目录兜底
  if [[ -z "$found" ]]; then
    for d in ${CUDA_SEARCH_DIRS:-/usr/local/cuda-* /usr/local/cuda*}; do
      if [[ -d "$d" && -x "$d/bin/nvcc" ]]; then
        found="$d"
        break
      fi
    done
  fi

  # 如果 nvcc 在 PATH 中，解析真实路径
  if [[ -z "$found" ]] && command -v nvcc >/dev/null 2>&1; then
    local nvcc_real
    nvcc_real="$(command -v nvcc)"
    # 处理 alternatives 符号链接链 (e.g. /usr/bin/nvcc -> /etc/alternatives/nvcc -> /usr/lib/cuda/bin/nvcc)
    if [[ -L "$nvcc_real" ]]; then
      nvcc_real="$(readlink -f "$nvcc_real")"
    fi
    local nvcc_dir
    nvcc_dir="$(dirname "$nvcc_real")"
    # 往上两级找 CUDA 安装根目录
    local cuda_root
    cuda_root="$(dirname "$nvcc_dir")"
    if [[ -d "$cuda_root/include" || -d "$cuda_root/lib64" ]]; then
      found="$cuda_root"
    fi
  fi

  # 最后兜底：查找 nvidia-cuda-toolkit 安装路径
  if [[ -z "$found" ]]; then
    if dpkg -l nvidia-cuda-toolkit 2>/dev/null | grep -q '^ii'; then
      found="/usr"
    fi
  fi

  if [[ -n "$found" ]]; then
    log "设置 /usr/local/cuda -> $found 并在当前环境导出 PATH/LD_LIBRARY_PATH/CUDA_HOME"
    # V0.6: 优先用 update-alternatives 管理 /usr/local/cuda（避免破坏系统原有管理），失败再直接建符号链接
    # 修复: 有 sudo 权限时也应创建链接（原逻辑因 /usr/local 无写权限而跳过）
    if sudo update-alternatives --set cuda "$found" 2>/dev/null; then
      :
    elif sudo ln -sfn "$found" /usr/local/cuda 2>/dev/null; then
      :
    elif [[ -w /usr/local || $(id -u) -eq 0 ]]; then
      ln -sfn "$found" /usr/local/cuda || true
    else
      warn "/usr/local 需要 root 权限才能创建符号链接，跳过创建，但将为当前脚本导出环境变量。"
    fi

    export PATH="$found/bin:$PATH"
    export LD_LIBRARY_PATH="$found/lib64:${LD_LIBRARY_PATH:-}"
    export CUDA_HOME="$found"
    return 0
  else
    warn "未找到已安装的 CUDA toolkit 二进制 (nvcc)。确保已安装并创建 /usr/local/cuda 指向正确版本，或手动将 nvcc 加入 PATH。"
    return 1
  fi
}

log() { echo -e "\n[INFO] $*\n"; }
warn() { echo -e "\n[WARN] $*\n"; }
err() { echo -e "\n[ERROR] $*\n"; }

ask_choice() {
  # $1 prompt, $2.. allowed options
  local prompt="$1"; shift
  local opts=("$@")
  local ans=""
  while true; do
    read -r -p "$prompt" ans
    for o in "${opts[@]}"; do
      if [[ "$ans" == "$o" ]]; then
        echo "$ans"
        return 0
      fi
    done
    echo "输入无效，请输入: ${opts[*]}"
  done
}

ask_path() {
  local prompt="$1"
  local default="$2"
  local ans=""
  read -r -p "$prompt (默认: $default): " ans
  if [[ -z "$ans" ]]; then
    ans="$default"
  fi
  # V0.6: 展开用户输入的 ~ 路径（如 ~/ros2_ws -> /home/xxx/ros2_ws）
  if [[ "$ans" == "~"* ]]; then
    ans="$HOME${ans:1}"
  fi
  echo "$ans"
}

bytes_to_gib() {
  awk -v b="$1" 'BEGIN { printf "%.1f", b/1024/1024/1024 }'
}

get_mem_swap_bytes() {
  local mem_kib swap_kib
  mem_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
  swap_kib="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)"

  mem_kib="${mem_kib:-0}"
  swap_kib="${swap_kib:-0}"

  echo "$((mem_kib * 1024)) $((swap_kib * 1024))"
}

ensure_total_mem_swap_at_least_32gib() {
  need_cmd awk

  local target_gib=32
  local target_bytes=$((target_gib * 1024 * 1024 * 1024))

  read -r mem_b swap_b < <(get_mem_swap_bytes)
  local total_b=$((mem_b + swap_b))

  log "检测内存与交换空间：\n  RAM  : $(bytes_to_gib "$mem_b") GiB\n  SWAP : $(bytes_to_gib "$swap_b") GiB\n  总计 : $(bytes_to_gib "$total_b") GiB\n  需求 : ${target_gib}.0 GiB (RAM+SWAP)\n"

  if (( total_b >= target_bytes )); then
    log "RAM+SWAP 已满足 >= 32GiB，继续安装。"
    return 0
  fi

  warn "RAM+SWAP 不足 32GiB，可能导致编译过程 OOM 或失败。"

  local need_b=$((target_bytes - total_b))
  local need_gib
  need_gib="$(bytes_to_gib "$need_b")"

  echo "需要额外增加约 ${need_gib} GiB 的 SWAP 才能达到 32GiB。"
  echo "请选择："
  echo "  1) 自动增加 SWAP（推荐）"
  echo "  2) 不增加并退出安装"
  local c
  c="$(ask_choice "请输入 1 或 2: " 1 2)"
  if [[ "$c" == "2" ]]; then
    err "用户拒绝将 RAM+SWAP 提升至 32GiB，安装程序退出。"
    exit 1
  fi

  local need_gib_ceil
  need_gib_ceil="$(awk -v b="$need_b" 'BEGIN { gib=b/1024/1024/1024; printf "%d", (gib==int(gib)?gib:int(gib)+1) }')"
  if [[ "$need_gib_ceil" -lt 1 ]]; then
    need_gib_ceil=1
  fi

  log "将创建/启用 swapfile 以增加 ${need_gib_ceil} GiB SWAP（使总量达到或超过 32GiB）。"
  create_or_extend_swapfile "$need_gib_ceil"

  read -r mem_b swap_b < <(get_mem_swap_bytes)
  total_b=$((mem_b + swap_b))
  log "扩容后：\n  RAM  : $(bytes_to_gib "$mem_b") GiB\n  SWAP : $(bytes_to_gib "$swap_b") GiB\n  总计 : $(bytes_to_gib "$total_b") GiB\n"
  if (( total_b < target_bytes )); then
    err "扩容后仍未达到 32GiB。请检查 swap 是否启用成功（swapon --show），然后重试。"
    exit 1
  fi

  log "RAM+SWAP 已达到 >= 32GiB，继续安装。"
}

create_or_extend_swapfile() {
  local add_gib="$1"

  need_cmd sudo
  need_cmd swapon
  need_cmd mkswap
  need_cmd chmod
  need_cmd grep
  need_cmd tee
  need_cmd getent
  command -v fallocate >/dev/null 2>&1 || true
  command -v dd >/dev/null 2>&1 || true

  local owner_user owner_home
  owner_user="${SUDO_USER:-$USER}"
  owner_home="$(getent passwd "$owner_user" | cut -d: -f6)"
  if [[ -z "$owner_home" ]]; then
    owner_home="$HOME"
  fi

  local base="${owner_home}/swapfile_glim"
  local target_file="$base"

  if sudo test -e "$target_file"; then
    local i=1
    while sudo test -e "${base}_${i}"; do i=$((i+1)); done
    target_file="${base}_${i}"
  fi

  log "创建 swap 文件：$target_file (大小 ${add_gib} GiB)"

  if command -v fallocate >/dev/null 2>&1; then
    sudo fallocate -l "${add_gib}G" "$target_file"
  else
    sudo dd if=/dev/zero of="$target_file" bs=1G count="$add_gib" status=progress
  fi

  sudo chmod 600 "$target_file"

  sudo mkswap "$target_file" >/dev/null
  sudo swapon "$target_file"

  if ! sudo grep -qE "^[^#].*\s${target_file}\s+swap\s" /etc/fstab; then
    echo "${target_file} none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
  fi

  log "Swap 已启用并写入 /etc/fstab：$target_file"
}

# ---------- Welcome ----------
welcome

# ---------- Auto install base tools & detect system ----------
auto_install_base_tools
detect_ubuntu_version

# ---------- Basic checks ----------
need_cmd sudo

# ---------- Detect ROS2 distro ----------
detect_ros2_distro

# Determine machine owner's home to avoid $HOME being /root when run via sudo
OWNER_USER="${SUDO_USER:-$USER}"
OWNER_HOME="$(getent passwd "$OWNER_USER" | cut -d: -f6)"
if [[ -z "$OWNER_HOME" ]]; then
  OWNER_HOME="$HOME"
fi
HOME_DIR="$OWNER_HOME"

# V1.2: 网络容错 —— GitHub 连接不稳定时自动重试克隆，失败时给出明确提示。
# retry_clone 定义被注入到每个 run_as_owner 子 shell 中，所有 git clone 均受益。
# 同时强制 git 使用 HTTP/1.1(规避 curl 16 HTTP2 framing 错误)并加大缓冲。
RETRY_CLONE_FUNC='
retry_clone() {
  local url="$1" dest="$2"; shift 2
  local name="${url##*/}"
  # V1.4: 私有仓库镜像版 —— 优先从镜像仓库下载固定版本源码快照，保证版本一致
  if [[ -n "${GLIM_MIRROR_REPO:-}" ]] && command -v gh >/dev/null 2>&1; then
    echo "[INFO] 从镜像仓库 $GLIM_MIRROR_REPO 下载 $name 固定版本源码快照..."
    if gh api "repos/$GLIM_MIRROR_REPO/contents/${name}.tar.gz" -H "Accept: application/vnd.github.raw" > "/tmp/${name}.tar.gz" 2>/dev/null \
      && mkdir -p "$dest" && tar -xzf "/tmp/${name}.tar.gz" -C "$dest" --strip-components=1; then
      rm -f "/tmp/${name}.tar.gz"
      touch "$dest/.glim_mirror"
      echo "[INFO] 已从镜像仓库取得 $name 源码快照(版本已固定)。"
      return 0
    fi
    rm -f "/tmp/${name}.tar.gz" 2>/dev/null || true
    echo "[WARN] 从镜像仓库下载 $name 失败，回退到 GitHub 直接克隆..."
  fi
  local i
  for i in 1 2 3; do
    echo "[INFO] 正在克隆 $url (第 $i/3 次尝试)..."
    if git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 clone "$@" "$url" "$dest"; then
      return 0
    fi
    echo "[WARN] 第 $i 次克隆失败，5 秒后自动重试..."
    sleep 5
  done
  echo ""
  echo "=============================================================="
  echo "  网络错误：无法获取源码（镜像仓库下载与 GitHub 克隆均失败）"
  echo "  仓库地址: $url"
  echo ""
  echo "  请按以下步骤排查后重新运行本脚本："
  echo "   1. 确认 gh 已登录且有权访问镜像仓库: gh auth status"
  echo "   2. 确认网络连通: ping github.com"
  echo "   3. 若使用代理，请先配置 git 代理或系统代理后重跑本脚本"
  echo "  已成功获取的仓库会被保留，重跑脚本可从断点继续，"
  echo "  无需重新下载已完成的部分。"
  echo "=============================================================="
  return 1
}
'

run_as_owner() {
  if [[ "$(id -u)" -eq 0 ]]; then
    # V1.1: 传递图形环境变量，保证以 sudo 运行时 GUI 仍能在用户桌面显示
    # V1.2: 注入 retry_clone 函数定义，使子 shell 中的克隆自动重试并友好报错
    sudo -u "$OWNER_USER" -H env DISPLAY="${DISPLAY:-}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" GLIM_MIRROR_REPO="${GLIM_MIRROR_REPO:-}" bash -lc "$RETRY_CLONE_FUNC"$'\n'"$*"
  else
    bash -lc "$RETRY_CLONE_FUNC"$'\n'"$*"
  fi
}

ensure_total_mem_swap_at_least_32gib

# ---------- Interactive selection ----------
echo "请选择安装版本："
echo "  1) CPU 版本"
echo "  2) GPU 版本"
ver_choice="$(ask_choice "请输入 1 或 2: " 1 2)"

MODE="cpu"
CUDA_VER=""
if [[ "$ver_choice" == "2" ]]; then
  MODE="gpu"
  echo ""
  echo "请选择 CUDA 版本："
  echo "  1) CUDA 12.2"
  echo "  2) CUDA 12.6"
  echo "  3) CUDA 13.1"
  cuda_choice="$(ask_choice "请输入 1/2/3: " 1 2 3)"
  case "$cuda_choice" in
    1) CUDA_VER="12.2" ;;
    2) CUDA_VER="12.6" ;;
    3) CUDA_VER="13.1" ;;
  esac

  # 校验 CUDA 版本与 Ubuntu 版本兼容性（CUDA 12.2 仅限 Ubuntu 22.04）
  if ! validate_cuda_ubuntu_compat "$CUDA_VER"; then
    err "CUDA 版本与当前 Ubuntu 版本不兼容，安装终止。"
    exit 1
  fi

  echo ""
  echo "是否尝试自动安装/更新与 CUDA ${CUDA_VER} 匹配的 NVIDIA 驱动？"
  echo "  1) 是，尝试自动安装/更新驱动（仅在支持 apt 的系统上）"
  echo "  2) 否，跳过驱动安装"
  drv_choice="$(ask_choice "请输入 1 或 2: " 1 2)"
  if [[ "$drv_choice" == "1" ]]; then
    install_nvidia_driver_for_cuda "$CUDA_VER" || true
    if command -v nvidia-smi >/dev/null 2>&1; then
      if ! nvidia-smi >/dev/null 2>&1; then
        warn "nvidia-smi 无法正常工作，驱动/库可能不匹配。通常需要重启系统以完成驱动安装并修复库匹配问题。"
        echo "建议现在重启系统（sudo reboot）后再继续编译步骤。"
      fi
    else
      warn "未检测到 nvidia-smi，驱动可能未安装成功。请手动检查驱动安装情况。"
    fi
  fi

  echo ""
  echo "是否现在尝试自动安装/重新安装 CUDA Toolkit ${CUDA_VER} ?"
  echo "  1) 是，尝试自动安装（仅在支持 apt 的系统上）"
  echo "  2) 否，跳过（保留系统现有 CUDA）"
  local_install_choice="$(ask_choice "请输入 1 或 2: " 1 2)"
  if [[ "$local_install_choice" == "1" ]]; then
    install_cuda_toolkit "$CUDA_VER" || true
    # 由于我们先安装了驱动，如果 toolkit 安装成功，尝试设置 symlink 与环境
    if [[ "${CUDA_AVAILABLE:-0}" -ne 1 ]]; then
      # 重新检测前先试着设置 symlink based on common install paths
      ensure_cuda_symlink_and_env "$CUDA_VER" || true
      detect_cuda
    fi
    if [[ "${CUDA_AVAILABLE:-0}" -ne 1 ]]; then
      warn "安装后未检测到 CUDA。若需手动安装，请参考： https://developer.nvidia.com/cuda-toolkit-archive"
    fi
  fi

  if [[ -n "$CUDA_VER" ]]; then
    # 验证 CUDA 与驱动兼容性
    verify_cuda_driver_compat "$CUDA_VER" || true
    # Ensure environment is set for subsequent build steps (in case toolkit was already present)
    ensure_cuda_symlink_and_env "$CUDA_VER" || true
    detect_cuda
  fi
fi

# 检测系统 CUDA 状态并根据结果调整构建选项
detect_cuda
if [[ "$MODE" == "gpu" && "${CUDA_AVAILABLE:-0}" -ne 1 ]]; then
  warn "你选择了 GPU 版本但系统未检测到 CUDA 工具链，编译将回退为 CPU 模式。"
  MODE="cpu"
  CUDA_VER=""
fi

WS_DIR="$(ask_path "请输入 ROS2 工作区路径(将会使用 <ws>/src 并 colcon build)" "${HOME_DIR}/ros2_ws")"

echo ""
echo "安装配置如下："
echo "  模式: $MODE"
echo "  CUDA版本: ${CUDA_VER:-无}"
echo "  ROS2发行版: $ROS2_DISTRO"
echo "  ROS2工作区: $WS_DIR"
echo "  第三方库安装前缀: $HOME_DIR/lib/<name>"
echo "----------------------------------------"
confirm="$(ask_choice "确认继续？(1=继续, 2=退出): " 1 2)"
if [[ "$confirm" == "2" ]]; then
  echo "已退出。"
  exit 0
fi

# ---------- Config ----------
JOBS="$(nproc)"
# V0.6: 内存小于 24GiB 时降低并行编译数，避免编译过程 OOM
read -r mem_b _ < <(get_mem_swap_bytes)
if (( mem_b < 24 * 1024 * 1024 * 1024 )) && (( JOBS > 8 )); then
  log "内存小于 24GiB，将并行编译数从 $JOBS 降低到 8，以避免 OOM。"
  JOBS=8
fi
# V1.3: 依据物理内存(不含 swap)单独限制 GTSAM 编译并行数。
# 实测 16GiB 内存机器上 GTSAM 用 -j8 会被内核 OOM 静默杀死(无报错、无产物)，-j4 稳定。
# V1.4 修复: 用 bash 原生 64 位算术计算，避免 awk 输出科学计数法(1.64972e+10)导致
#           (( )) 报语法错误，也避免 printf %d 被截断为 int32 上限(2147483647)。
RAM_BYTES="$(( $(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null) * 1024 ))"
GTSAM_JOBS="$JOBS"
if (( RAM_BYTES < 24 * 1024 * 1024 * 1024 )); then
  if (( JOBS > 8 )); then
    log "物理内存不足 24GiB，将全局并行编译数从 $JOBS 降低到 8。"
    JOBS=8
  fi
  GTSAM_JOBS=4
  log "物理内存不足 24GiB，GTSAM 编译并行数限制为 4，避免 OOM。"
fi
# V1.4: 私有镜像仓库(存放各依赖库的固定版本源码快照)。
# 本版优先从该仓库下载快照(版本固定)，GitHub 直连仅作回退。
export GLIM_MIRROR_REPO="${GLIM_MIRROR_REPO:-GZ89mid/GLIMinstall}"
SRC_DIR="$HOME_DIR/src"
LIB_ROOT="$HOME_DIR/lib"

GTSAM_REF="4.3a1"
BUILD_VIEWER="ON"
MARCH_NATIVE="OFF"

mkdir -p "$LIB_ROOT"
mkdir -p "$LIB_ROOT/gtsam" "$LIB_ROOT/iridescence" "$LIB_ROOT/gtsam_points"
LIB_SRC_DIR="$LIB_ROOT/src"
mkdir -p "$LIB_SRC_DIR"
if [[ "$(id -u)" -eq 0 ]]; then
  sudo chown -R "$OWNER_USER":"$OWNER_USER" "$LIB_ROOT" "$LIB_SRC_DIR" || true
fi

# ---------- 第三方库检测与清理(可选) ----------
# V1.3: 逐库检测安装状态(安装标记文件)，让用户选择"补全缺失库"或"全盘重新编译克隆"。
# 安装标记:
#   GTSAM:        lib/libgtsam.so + lib/cmake/GTSAM/GTSAMConfig.cmake
#   iridescence:  lib/libiridescence.so
#   gtsam_points: lib/cmake/gtsam_points/gtsam_points-config.cmake
SKIP_GTSAM=0; SKIP_IRID=0; SKIP_GP=0
LIB_REBUILT=0
CLEAN_LIBS="auto"
lib_ok_gtsam() { [[ -f "$LIB_ROOT/gtsam/lib/libgtsam.so" && -f "$LIB_ROOT/gtsam/lib/cmake/GTSAM/GTSAMConfig.cmake" ]]; }
lib_ok_irid()  { [[ -f "$LIB_ROOT/iridescence/lib/libiridescence.so" ]]; }
lib_ok_gp()    { [[ -f "$LIB_ROOT/gtsam_points/lib/cmake/gtsam_points/gtsam_points-config.cmake" ]]; }

cleanup_libs_menu() {
  local st_gtsam st_irid st_gp missing=0
  if lib_ok_gtsam; then st_gtsam="✅ 已安装"; else st_gtsam="❌ 缺失"; missing=1; fi
  if lib_ok_irid;  then st_irid="✅ 已安装";  else st_irid="❌ 缺失";  missing=1; fi
  if lib_ok_gp;    then st_gp="✅ 已安装";    else st_gp="❌ 缺失";    missing=1; fi

  echo ""
  echo "第三方库安装状态检测:"
  echo "  GTSAM ($GTSAM_REF):   $st_gtsam"
  echo "  iridescence:      $st_irid"
  echo "  gtsam_points:     $st_gp"

  local c
  if [[ "$missing" -eq 0 ]]; then
    echo "所有第三方库均已安装完整，请选择："
    echo "  1) 直接复用现有库，跳过编译（最快）"
    echo "  2) 全盘重新编译克隆（删除安装目录与源码 clone，最稳妥，耗时最长）"
    echo "  3) 仅清理编译缓存并重编（保留源码 clone）"
    c="$(ask_choice "请选择 1/2/3: " 1 2 3)"
  else
    echo "检测到缺失的库，请选择："
    echo "  1) 仅补全缺失的库（已安装好的直接复用，最快，推荐）"
    echo "  2) 全盘重新编译克隆（删除安装目录与源码 clone，最稳妥，耗时最长）"
    echo "  3) 仅清理编译缓存并重编（保留源码 clone）"
    c="$(ask_choice "请选择 1/2/3: " 1 2 3)"
  fi
  case "$c" in
    1) CLEAN_LIBS="auto" ;;
    2) CLEAN_LIBS="full" ;;
    3) CLEAN_LIBS="cache" ;;
  esac

  case "$CLEAN_LIBS" in
    full)
      log "清理模式: 全盘重新编译克隆"
      run_as_owner "rm -rf '$LIB_ROOT/gtsam' '$LIB_ROOT/gtsam_points' '$LIB_ROOT/iridescence' '$LIB_SRC_DIR/gtsam' '$LIB_SRC_DIR/gtsam_points' '$LIB_SRC_DIR/iridescence'"
      ;;
    cache)
      log "清理模式: 清理编译缓存与安装目录(保留源码 clone)"
      run_as_owner "rm -rf '$LIB_ROOT/gtsam' '$LIB_ROOT/gtsam_points' '$LIB_ROOT/iridescence' '$LIB_SRC_DIR/gtsam/build' '$LIB_SRC_DIR/gtsam_points/build' '$LIB_SRC_DIR/iridescence/build'"
      ;;
    auto)
      # 补全模式: 已安装完整的库直接复用，只重建缺失的库
      log "清理模式: 自动检测并仅补全缺失的库"
      if lib_ok_gtsam; then
        SKIP_GTSAM=1; log "GTSAM 已安装完整，直接复用。"
      else
        run_as_owner "rm -rf '$LIB_ROOT/gtsam'"
        log "GTSAM 缺失，将编译安装。"
      fi
      if lib_ok_irid; then
        SKIP_IRID=1; log "iridescence 已安装完整，直接复用。"
      else
        run_as_owner "rm -rf '$LIB_ROOT/iridescence'"
        log "iridescence 缺失，将编译安装。"
      fi
      if lib_ok_gp; then
        SKIP_GP=1; log "gtsam_points 已安装完整，直接复用。"
      else
        run_as_owner "rm -rf '$LIB_ROOT/gtsam_points'"
        log "gtsam_points 缺失，将编译安装。"
      fi
      ;;
  esac

  # 清理后重建目录结构
  mkdir -p "$LIB_ROOT"
  mkdir -p "$LIB_ROOT/gtsam" "$LIB_ROOT/iridescence" "$LIB_ROOT/gtsam_points"
  mkdir -p "$LIB_SRC_DIR"
}
cleanup_libs_menu

# ---------- System deps (apt) ----------
# V0.6: 全新机器未装 ROS2 时，先配置 ROS2 apt 源再安装 ros-base
setup_ros2_repo
log "安装系统依赖（apt）..."
sudo apt update
sudo apt install -y \
  build-essential pkg-config \
  libomp-dev libboost-all-dev libmetis-dev \
  libfmt-dev libspdlog-dev \
  libglm-dev libglfw3-dev libpng-dev libjpeg-dev \
  libgl1-mesa-dev libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev \
  python3-colcon-common-extensions \
  ros-${ROS2_DISTRO}-ros-base \
  ros-${ROS2_DISTRO}-pcl-ros \
  ros-${ROS2_DISTRO}-tf2-ros \
  ros-${ROS2_DISTRO}-tf2-eigen \
  ros-${ROS2_DISTRO}-rviz2

# V0.6: 首次安装 ROS2 时，确认安装是否成功（原脚本在安装前就要求 setup.bash 存在）
if [[ "${ROS2_INSTALL_NEEDED:-0}" -eq 1 ]]; then
  if [[ -f "$ROS2_SETUP" ]]; then
    log "ROS2 $ROS2_DISTRO 已安装完成。"
  else
    err "ROS2 $ROS2_DISTRO 安装后仍找不到 $ROS2_SETUP，请手动安装 ROS2 后重试。"
    exit 1
  fi
fi

if [[ "$MODE" == "gpu" ]]; then
  if ! command -v nvcc >/dev/null 2>&1; then
    warn "未检测到 nvcc，CUDA Toolkit 可能未安装或未加入 PATH。\n你选择的 CUDA 版本是 ${CUDA_VER}，若后续编译失败，请先安装对应 CUDA Toolkit。"
  fi
fi

# ... rest of original script unchanged (build steps identical to V0.1) ...

# Build & install GTSAM / Iridescence / gtsam_points
# V1.1: 复用模式跳过编译
# V1.3: GTSAM 改为浅克隆(--depth 1 --branch 4.3a1，数据量小、网络稳定性高)；
#       编译并行数用 GTSAM_JOBS(内存小的机器为 4，避免 OOM 静默被杀)；
#       支持镜像快照(.glim_mirror 标记时跳过 git 操作)。
# V1.6: 提速改造 —— ①三个库的克隆相互独立，并行执行；②GTSAM 与 iridescence
#       编译相互独立，并行执行；③gtsam_points 依赖前两者，等其完成后单独编译。
#       并行任务输出统一加行前缀(如 [克隆:gtsam] / [编译:iridescence])，
#       同时写入 /tmp 日志；失败时自动打印各日志尾部并中止。

# ---------- 阶段一: 并行克隆源码 ----------
log "并行克隆第三方库源码 (gtsam / iridescence / gtsam_points)..."
CLONE_LOG_DIR="$(mktemp -d /tmp/glim_clone.XXXXXX)"
CLONE_PIDS=()

if [[ "$SKIP_GTSAM" -eq 1 ]]; then
  log "复用现有 GTSAM 安装，跳过克隆与编译。"
else
  ( set +e
    run_as_owner "cd '$LIB_SRC_DIR' && if [[ -d gtsam && ! -d gtsam/.git && ! -f gtsam/.glim_mirror ]]; then echo '[WARN] 发现非 git 目录 $LIB_SRC_DIR/gtsam，正在移除并重新克隆'; rm -rf gtsam; fi; if [[ ! -d gtsam ]]; then retry_clone https://github.com/borglab/gtsam gtsam --depth 1 --branch '$GTSAM_REF' || exit 1; fi && cd gtsam && if [[ -d .git ]]; then git checkout '$GTSAM_REF' 2>/dev/null || { echo '[WARN] 本地仓库缺少 $GTSAM_REF 版本，重新浅克隆...'; cd .. && rm -rf gtsam && retry_clone https://github.com/borglab/gtsam gtsam --depth 1 --branch '$GTSAM_REF' || exit 1; cd gtsam; }; else echo '[INFO] gtsam 源码来自镜像快照(版本已固定为 $GTSAM_REF)，跳过 git 操作。'; fi" 2>&1 | sed -u 's/^/[克隆:gtsam] /' | tee "$CLONE_LOG_DIR/gtsam.log"
    echo "${PIPESTATUS[0]}" > "$CLONE_LOG_DIR/gtsam.status"
  ) &
  CLONE_PIDS+=($!)
fi

if [[ "$SKIP_IRID" -eq 1 ]]; then
  log "复用现有 iridescence 安装，跳过克隆与编译。"
else
  ( set +e
    run_as_owner "cd '$LIB_SRC_DIR' && if [[ -d iridescence && ! -d iridescence/.git && ! -f iridescence/.glim_mirror ]]; then echo '[WARN] 发现非 git 目录 $LIB_SRC_DIR/iridescence，正在移除并重新克隆'; rm -rf iridescence; fi; if [[ ! -d iridescence ]]; then retry_clone https://github.com/koide3/iridescence iridescence --recursive || exit 1; fi" 2>&1 | sed -u 's/^/[克隆:iridescence] /' | tee "$CLONE_LOG_DIR/iridescence.log"
    echo "${PIPESTATUS[0]}" > "$CLONE_LOG_DIR/iridescence.status"
  ) &
  CLONE_PIDS+=($!)
fi

if [[ "$SKIP_GP" -eq 1 ]]; then
  log "复用现有 gtsam_points 安装，跳过克隆与编译。"
else
  ( set +e
    run_as_owner "cd '$LIB_SRC_DIR' && if [[ -d gtsam_points && ! -d gtsam_points/.git && ! -f gtsam_points/.glim_mirror ]]; then echo '[WARN] 发现非 git 目录 $LIB_SRC_DIR/gtsam_points，正在移除并重新克隆'; rm -rf gtsam_points; fi; if [[ ! -d gtsam_points ]]; then retry_clone https://github.com/koide3/gtsam_points gtsam_points || exit 1; elif [[ -d gtsam_points/.git ]]; then echo '[INFO] gtsam_points 已存在，正在更新到最新 master...'; (cd gtsam_points && git -c http.version=HTTP/1.1 fetch origin && git checkout master && git pull --ff-only); else echo '[INFO] gtsam_points 源码来自镜像快照，跳过 git 操作。'; fi" 2>&1 | sed -u 's/^/[克隆:gtsam_points] /' | tee "$CLONE_LOG_DIR/gtsam_points.log"
    echo "${PIPESTATUS[0]}" > "$CLONE_LOG_DIR/gtsam_points.status"
  ) &
  CLONE_PIDS+=($!)
fi

for p in "${CLONE_PIDS[@]}"; do
  wait "$p" || true
done
CLONE_FAILED=0
for s in "$CLONE_LOG_DIR"/*.status; do
  [[ -f "$s" ]] || continue
  if [[ "$(cat "$s")" != "0" ]]; then
    CLONE_FAILED=1
    warn "克隆任务失败: $(basename "$s" .status)"
  fi
done
if [[ "$CLONE_FAILED" -eq 1 ]]; then
  for f in "$CLONE_LOG_DIR"/*.log; do
    echo "----------------------------------------"
    echo "克隆日志: $(basename "$f")"
    tail -n 30 "$f" 2>/dev/null
  done
  err "部分源码克隆失败，请根据上方日志排查(完整日志保留在 $CLONE_LOG_DIR)。"
  exit 1
fi
rm -rf "$CLONE_LOG_DIR"

# ---------- 阶段二: 并行编译 GTSAM + iridescence ----------
# V1.6: 两者无相互依赖，并行编译；低内存机器上 iridescence 限为 2 个并行任务，
#       为 GTSAM 保留内存余量(此前 GTSAM 单库 -j8 曾 OOM 被静默杀)。
IRID_JOBS="$JOBS"
if [[ "$SKIP_GTSAM" -eq 0 && "$SKIP_IRID" -eq 0 ]] && (( RAM_BYTES < 24 * 1024 * 1024 * 1024 )); then
  IRID_JOBS=2
  log "GTSAM 与 iridescence 将并行编译，物理内存不足 24GiB，iridescence 并行数限制为 $IRID_JOBS。"
fi

BUILD_LOG_DIR="$(mktemp -d /tmp/glim_build.XXXXXX)"
BUILD_PIDS=()

if [[ "$SKIP_GTSAM" -eq 1 ]]; then
  : # 已在阶段一输出跳过信息
else
  log "编译安装 GTSAM ($GTSAM_REF) -> $LIB_ROOT/gtsam"
  LIB_REBUILT=1
  ( set +e
    run_as_owner "cd '$LIB_SRC_DIR/gtsam' && rm -rf build && mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX='$LIB_ROOT/gtsam' -DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF -DGTSAM_BUILD_TESTS=OFF -DGTSAM_WITH_TBB=OFF -DGTSAM_USE_SYSTEM_EIGEN=ON -DGTSAM_BUILD_WITH_MARCH_NATIVE=OFF -DGTSAM_TANGENT_PREINTEGRATION=ON && make -j'$GTSAM_JOBS' && make install" 2>&1 | sed -u 's/^/[编译:gtsam] /' | tee "$BUILD_LOG_DIR/gtsam.log"
    echo "${PIPESTATUS[0]}" > "$BUILD_LOG_DIR/gtsam.status"
  ) &
  BUILD_PIDS+=($!)
fi

if [[ "$SKIP_IRID" -eq 1 ]]; then
  : # 已在阶段一输出跳过信息
else
  log "编译安装 Iridescence -> $LIB_ROOT/iridescence"
  LIB_REBUILT=1
  ( set +e
    run_as_owner "cd '$LIB_SRC_DIR/iridescence' && if [[ -d .git ]]; then git submodule update --init --recursive; else echo '[INFO] iridescence 源码来自镜像快照(含全部 submodule)，跳过 git 操作。'; fi && rm -rf build && mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX='$LIB_ROOT/iridescence' && make -j'$IRID_JOBS' && make install" 2>&1 | sed -u 's/^/[编译:iridescence] /' | tee "$BUILD_LOG_DIR/iridescence.log"
    echo "${PIPESTATUS[0]}" > "$BUILD_LOG_DIR/iridescence.status"
  ) &
  BUILD_PIDS+=($!)
fi

for p in "${BUILD_PIDS[@]}"; do
  wait "$p" || true
done
BUILD_FAILED=0
for s in "$BUILD_LOG_DIR"/*.status; do
  [[ -f "$s" ]] || continue
  if [[ "$(cat "$s")" != "0" ]]; then
    BUILD_FAILED=1
    warn "编译任务失败: $(basename "$s" .status)"
  fi
done
if [[ "$BUILD_FAILED" -eq 1 ]]; then
  for f in "$BUILD_LOG_DIR"/*.log; do
    echo "----------------------------------------"
    echo "编译日志: $(basename "$f")"
    tail -n 40 "$f" 2>/dev/null
  done
  err "部分库编译失败，请根据上方日志排查(完整日志保留在 $BUILD_LOG_DIR)。"
  exit 1
fi
rm -rf "$BUILD_LOG_DIR"

# ---------- 阶段三: 编译 gtsam_points (依赖 GTSAM + iridescence) ----------
BUILD_WITH_CUDA="OFF"
if [[ "$MODE" == "gpu" ]]; then
  BUILD_WITH_CUDA="ON"
fi

if [[ "$SKIP_GP" -eq 1 ]]; then
  : # 已在阶段一输出跳过信息
else
  log "编译安装 gtsam_points -> $LIB_ROOT/gtsam_points"
  LIB_REBUILT=1
  if [[ "$BUILD_WITH_CUDA" == "ON" ]]; then
    run_as_owner "export PATH=/usr/local/cuda/bin:\$PATH; export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH; export CUDA_HOME=/usr/local/cuda; cd '$LIB_SRC_DIR/gtsam_points' && rm -rf build && mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX='$LIB_ROOT/gtsam_points' -DBUILD_WITH_CUDA='$BUILD_WITH_CUDA' -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DGTSAM_DIR='$LIB_ROOT/gtsam/lib/cmake/GTSAM' -DCMAKE_PREFIX_PATH='$LIB_ROOT/gtsam;$LIB_ROOT/iridescence' && make -j'$JOBS' && make install"
  else
    run_as_owner "cd '$LIB_SRC_DIR/gtsam_points' && rm -rf build && mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX='$LIB_ROOT/gtsam_points' -DBUILD_WITH_CUDA='$BUILD_WITH_CUDA' -DGTSAM_DIR='$LIB_ROOT/gtsam/lib/cmake/GTSAM' -DCMAKE_PREFIX_PATH='$LIB_ROOT/gtsam;$LIB_ROOT/iridescence' && make -j'$JOBS' && make install"
  fi
fi

# ldconfig
log "写入动态库路径并执行 ldconfig"
CONF_FILE="/etc/ld.so.conf.d/glim_local_libs.conf"
sudo bash -c "cat > '$CONF_FILE' <<EOF
$LIB_ROOT/gtsam/lib
$LIB_ROOT/iridescence/lib
$LIB_ROOT/gtsam_points/lib
EOF"
sudo ldconfig

# V0.9 修复: 删除旧版脚本遗留在 /usr/local 的旧 gtsam_points。
# 旧版(1.2.2)版本号恰好能满足 glim 的 find_package(gtsam_points 1.2.2 REQUIRED)，
# 会被 CMake 版本回退选中，但它缺少 has_index 等新 API，导致编译失败。
if [[ -d /usr/local/include/gtsam_points || -d /usr/local/lib/cmake/gtsam_points ]] || ls /usr/local/lib/libgtsam_points*.so* >/dev/null 2>&1; then
  warn "检测到 /usr/local 中残留旧版 gtsam_points（旧版脚本安装），正在删除以消除版本冲突..."
  sudo rm -rf /usr/local/include/gtsam_points /usr/local/lib/cmake/gtsam_points /usr/local/lib/libgtsam_points*
fi

# V1.0 修复: 删除 /usr/local 中残留的旧 GTSAM（旧版脚本/手动安装）。
# 残留的 GTSAM 可能被 find_package 误选中，其头文件/库与本脚本编译的 ~/lib GTSAM
# 不一致时（如缺少 PreintegratedImuMeasurementsT 符号）会导致链接失败。
if [[ -d /usr/local/include/gtsam || -d /usr/local/lib/cmake/GTSAM ]] || ls /usr/local/lib/libgtsam*.so* >/dev/null 2>&1; then
  warn "检测到 /usr/local 中残留旧版 GTSAM（旧版脚本/手动安装），正在删除以消除版本冲突..."
  sudo rm -rf /usr/local/include/gtsam /usr/local/include/gtsam_unstable \
    /usr/local/lib/cmake/GTSAM /usr/local/lib/cmake/GTSAM_UNSTABLE /usr/local/lib/cmake/GTSAMCMakeTools \
    /usr/local/lib/libgtsam* /usr/local/lib/libmetis-gtsam* /usr/local/lib/libcephes-gtsam*
fi

# V1.6 修复: 删除 /opt/ros/humble 中残留的旧 glim/glim_ros(旧版脚本/手动安装)。
# 残留的旧 libglim.so / libinteractive_viewer.so 缺少新版本符号(如 OfflineViewer
# 双参构造 _ZN4glim13OfflineViewerC1E...ES8_)，若运行时动态加载器优先找到它们，
# 会报 undefined symbol 导致 offline_viewer 启动失败(exit 127)。
if [[ -d /opt/ros/humble/share/glim || -d /opt/ros/humble/include/glim ]] || ls /opt/ros/humble/lib/libglim.so /opt/ros/humble/lib/libglim_ros.so /opt/ros/humble/lib/libinteractive_viewer.so >/dev/null 2>&1; then
  warn "检测到 /opt/ros/humble 中残留旧版 glim/glim_ros(旧版脚本/手动安装)，正在删除以消除动态库冲突..."
  sudo rm -rf /opt/ros/humble/share/glim /opt/ros/humble/share/glim_ros \
    /opt/ros/humble/include/glim /opt/ros/humble/include/glim_ros \
    /opt/ros/humble/lib/libglim.so /opt/ros/humble/lib/libglim_ros.so \
    /opt/ros/humble/lib/libinteractive_viewer.so
fi

# ROS2 workspace build
log "配置并编译 ROS2 工作区: $WS_DIR"
# V0.9 修复: glim/glim_ros2 已存在时也更新到最新 master，
# 避免旧 clone 的 glim 与新版 gtsam_points 之间出现 API 不匹配。
run_as_owner "mkdir -p '$WS_DIR/src' && cd '$WS_DIR/src' && if [[ ! -d 'glim' ]]; then retry_clone https://github.com/koide3/glim glim || exit 1; elif [[ -d glim/.git ]]; then echo '[INFO] glim 已存在，正在更新到最新 master...'; (cd glim && git -c http.version=HTTP/1.1 fetch origin && git checkout master && git pull --ff-only); else echo '[INFO] glim 源码来自镜像快照，跳过 git 操作。'; fi && if [[ ! -d 'glim_ros2' ]]; then retry_clone https://github.com/koide3/glim_ros2 glim_ros2 || exit 1; elif [[ -d glim_ros2/.git ]]; then echo '[INFO] glim_ros2 已存在，正在更新到最新 master...'; (cd glim_ros2 && git -c http.version=HTTP/1.1 fetch origin && git checkout master && git pull --ff-only); else echo '[INFO] glim_ros2 源码来自镜像快照，跳过 git 操作。'; fi"

# V0.6: 清理指向 /usr/local 旧库的 CMake 缓存（防止系统残留旧版 gtsam/gtsam_points/iridescence
# 导致 find_package 找到错误版本而编译失败）
run_as_owner "for f in '$WS_DIR'/build/*/CMakeCache.txt; do
  [ -f \"\$f\" ] || continue
  if grep -qE '^((GTSAM|gtsam_points|Iridescence)_DIR):PATH=/usr/local/' \"\$f\"; then
    pkg=\"\$(basename \"\$(dirname \"\$f\")\")\"
    echo '[INFO] 检测到 $WS_DIR/build/\$pkg 缓存了 /usr/local 旧库路径，清除该包缓存以使用 ~/lib 新库'
    rm -rf \"\$WS_DIR/build/\$pkg\"
  fi
done"

# V1.3 修复: 仅当本次实际重新编译了第三方库时，才清除 glim/glim_ros 的 colcon
# 构建缓存，强制其针对新库重新配置与链接，避免混链导致 GUI 启动崩溃。
# (复用模式且库完整时无需清理，保持最快启动)
if [[ "$LIB_REBUILT" -eq 1 ]]; then
  log "第三方库已重新编译，清理 glim/glim_ros 的 colcon 构建缓存以强制重新链接。"
  run_as_owner "rm -rf '$WS_DIR/build/glim' '$WS_DIR/build/glim_ros'"
fi

run_as_owner "source '$ROS2_SETUP' && export CMAKE_PREFIX_PATH='$LIB_ROOT/gtsam:$LIB_ROOT/iridescence:$LIB_ROOT/gtsam_points'; export LD_LIBRARY_PATH=\"$LIB_ROOT/gtsam/lib:$LIB_ROOT/iridescence/lib:$LIB_ROOT/gtsam_points/lib:\$LD_LIBRARY_PATH\"; cd '$WS_DIR' && colcon build --base-paths src --cmake-args -DBUILD_WITH_CUDA='$BUILD_WITH_CUDA' -DBUILD_WITH_VIEWER='ON' -DBUILD_WITH_MARCH_NATIVE='OFF' -DCMAKE_PREFIX_PATH='$LIB_ROOT/gtsam;$LIB_ROOT/iridescence;$LIB_ROOT/gtsam_points' -DGTSAM_DIR='$LIB_ROOT/gtsam/lib/cmake/GTSAM'"

# V1.1 新增: 检查 GLIM 图形化界面所需的运行环境(显示环境 + OpenGL/GLFW/iridescence)
check_gui_env() {
  local gui_ok=1
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    gui_ok=0
    warn "未检测到图形显示环境 (\$DISPLAY / \$WAYLAND_DISPLAY 为空)。"
    echo "  GUI 程序 (offline_viewer / map_editor / rviz2) 需要图形桌面环境才能启动。"
    echo "  若通过 SSH 远程连接，请使用带 X 转发的连接 (ssh -X)，或在本地图形终端中运行。"
  fi
  # V1.4 修复: grep -q 匹配即退出会让 ldconfig 收到 SIGPIPE，配合 set -o pipefail
  #           会误报库不存在。去掉 -q 改用 >/dev/null，让 grep 读完整输入。
  if ! ldconfig -p 2>/dev/null | grep -E 'libglfw' >/dev/null; then
    gui_ok=0
    warn "未找到 GLFW 库，GUI 窗口可能无法创建。请安装: sudo apt install -y libglfw3"
  fi
  if ! ldconfig -p 2>/dev/null | grep -E 'libGLX|libGL\.so' >/dev/null; then
    gui_ok=0
    warn "未找到 OpenGL 库，GUI 渲染可能失败。请安装: sudo apt install -y libgl1-mesa-glx"
  fi
  if ! ldconfig -p 2>/dev/null | grep -E 'libiridescence' >/dev/null; then
    gui_ok=0
    warn "未找到 iridescence 库(渲染器)。请重新运行脚本并选择清理重装(选项 1 或 2)。"
  fi
  if [[ "$gui_ok" -eq 1 ]]; then
    log "图形化界面运行环境检查通过(显示环境 + OpenGL/GLFW/iridescence 均可用)。"
  fi
  return 0
}

verify_install() {
  log "验证安装：检查 GLIM 可执行文件与图形界面启动能力"
  if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    log "检测到图形环境，尝试启动 GLIM 图形界面 (offline_viewer，12 秒后自动关闭)..."
    run_as_owner "source '$ROS2_SETUP' && cd '$WS_DIR' && source install/setup.bash >/dev/null 2>&1; export LD_LIBRARY_PATH=\"$LIB_ROOT/gtsam/lib:$LIB_ROOT/iridescence/lib:$LIB_ROOT/gtsam_points/lib:\$LD_LIBRARY_PATH\"; timeout 12 ros2 run glim_ros offline_viewer &> '$HOME_DIR/install_verify.log' || true"
    if run_as_owner "grep -qE 'config_path' '$HOME_DIR/install_verify.log'"; then
      log "验证成功：offline_viewer 图形界面已正常启动并输出日志。查看验证日志： $HOME_DIR/install_verify.log"
    else
      warn "GUI 启动日志异常，请查看： $HOME_DIR/install_verify.log"
    fi
  else
    log "无图形显示环境，改为无头验证（确认可执行文件与动态库可正常加载）..."
    run_as_owner "source '$ROS2_SETUP' && cd '$WS_DIR' && source install/setup.bash >/dev/null 2>&1; export LD_LIBRARY_PATH=\"$LIB_ROOT/gtsam/lib:$LIB_ROOT/iridescence/lib:$LIB_ROOT/gtsam_points/lib:\$LD_LIBRARY_PATH\"; ros2 run glim_ros offline_viewer --help &> '$HOME_DIR/install_verify.log' || true"
    if run_as_owner "grep -qE 'map_path|config_path' '$HOME_DIR/install_verify.log'"; then
      log "无头验证通过：offline_viewer 可正常加载（动态库链接完整）。"
    else
      warn "无头验证异常，请查看： $HOME_DIR/install_verify.log"
    fi
  fi
}

verify_install
check_gui_env

log "安装完成！\n下一步：\n  1) source ROS2 环境: source \"$ROS2_SETUP\"\n  2) source 工作区：\n     source \"$WS_DIR/install/setup.bash\"\n\nGLIM 图形化界面启动方式：\n  - rviz2 实时可视化(需先启动 glim_rosnode 接收传感器数据):\n      source \"$ROS2_SETUP\"; source \"$WS_DIR/install/setup.bash\"\n      rviz2 -d \"$WS_DIR/src/glim_ros2/rviz/glim_ros.rviz\"\n  - 交互式查看器(可视化已有地图/点云):\n      ros2 run glim_ros offline_viewer [map_path]\n  - 地图编辑界面:\n      ros2 run glim_ros map_editor <map_path>\n\nSwap 变更提示：\n  - 脚本可能创建了 ~/swapfile_glim* 并写入 /etc/fstab\n  - 可用 'swapon --show' 查看当前 swap\n"

# V1.1 新增: 图形环境下询问是否立即启动 GLIM 图形化界面
if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
  echo ""
  echo "是否立即启动 glim 图形化界面？"
  echo "  1) 启动 rviz2 实时可视化界面"
  echo "  2) 启动 offline_viewer 交互查看器"
  echo "  3) 跳过，稍后自行启动"
  gui_choice="$(ask_choice "请选择 1/2/3: " 1 2 3)"
  case "$gui_choice" in
    1)
      log "正在启动 rviz2(关闭 rviz2 窗口后脚本结束)..."
      run_as_owner "source '$ROS2_SETUP' && cd '$WS_DIR' && source install/setup.bash >/dev/null 2>&1; export LD_LIBRARY_PATH=\"$LIB_ROOT/gtsam/lib:$LIB_ROOT/iridescence/lib:$LIB_ROOT/gtsam_points/lib:\$LD_LIBRARY_PATH\"; rviz2 -d '$WS_DIR/src/glim_ros2/rviz/glim_ros.rviz'"
      ;;
    2)
      log "正在启动 offline_viewer(关闭窗口后脚本结束)..."
      run_as_owner "source '$ROS2_SETUP' && cd '$WS_DIR' && source install/setup.bash >/dev/null 2>&1; export LD_LIBRARY_PATH=\"$LIB_ROOT/gtsam/lib:$LIB_ROOT/iridescence/lib:$LIB_ROOT/gtsam_points/lib:\$LD_LIBRARY_PATH\"; ros2 run glim_ros offline_viewer"
      ;;
    3)
      ;;
  esac
else
  warn "当前会话没有图形显示环境，无法立即启动 GUI。请在图形桌面的终端中执行上述启动命令。"
fi
