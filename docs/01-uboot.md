### U-boot

在實作作業系統之前，我們必須完成 Bootloader 的建置，並成功跳轉至 OS kernal，透過 UART 輸出訊息。

#### U-boot

U-Boot（Universal Boot Loader）是嵌入式系統中最主流的開機引導程式。它就像是 PC 上的 BIOS / UEFI，負責在硬體剛通電時接管系統。

U-Boot 必須幫我們做以下事項：

- 初始化硬體 (timer, 記憶體控制器)。
- 提供基礎的週邊驅動（如 SD 卡、eMMC、網路、UART）。
- 提供 CLI 介面方便除錯。
- 將真正的作業系統從儲存裝置 load 到記憶體中並執行。

#### 為什麼我們需要 U-boot？

我對開發 bootloader 與硬體方面的知識不是非常熟悉，且會牽扯到許多非作業系統的問題，因此選擇跳過此步驟，使用簡單的方式。

未來能力許可時，有機會再來試試看 bootloader 完全自己手搓。

#### Trusted Firmware-A (TF-A)

在 ARMv8 (64bit) 架構中，TF-A 是整顆晶片權限最高的人，ARM 架構將 CPU 權限分級 (Exception Levels, EL) 為 EL0 ~ EL3，數字越大表示權限越大。

- EL0 (User)：最低權限，用來跑一般的應用程式（App）。
- EL1 (OS Kernel)：作業系統核心（如 Linux Kernel，或你的 Bare-Metal OS）運行的層級。
- EL2 (Hypervisor)：虛擬機監視器層級，通常 U-Boot 本體會在這個層級執行，準備好環境後再降級把控制權交給 OS。
- EL3 (Secure Monitor)：最高權限的「安全監控層」。TF-A 就是永遠常駐在 EL3 的程式。

TF-A 在開機的過程扮演著十分重要的角色，當 Orange Pi Zero 3 通電時，最底層的硬體 BROM 與 U-Boot SPL 負責把 DRAM 喚醒。接著 SPL 不會直接呼叫 U-Boot，而是先呼叫 TF-A。

:::spoiler 名詞解釋: Bootstrap Read-Only Memory (BROM)
*Bootstrap Read-Only Memory (BROM)：BROM 是嵌入在處理器晶片或主板韌體中的一小段唯讀程式碼。它是裝置在接通電源（Power-on）或重置（Reset）時，CPU執行的第一段程式碼。*
:::

:::spoiler 名詞解釋: SPL (Secondary Program Loader)
*SPL (Secondary Program Loader)：晶片剛通電時是無法使用 DRAM 的，CPU 唯一能使用的記憶體只有極小的 SRAM，完整的 U-Boot + TF-A 無法塞進 SRAM。因此在 U-Boot 編譯時，會切出一個體積很小的版本，我們稱之為 SPL，SPL 需要幫我們初始化 DRAM，DRAM 成功喚醒後，SPL 就會幫我們把 TF-A、U-Boot 本體搬到 DRAM 中，並結束他的職責。*
:::


TF-A 會協助我們做以下事情：

1. 把系統硬體劃分為 Secure World 與 Normal World
2. 環境設定完成後，TF-A 將 CPU 權限從 EL3 降級到 EL2，並將控制權交給 U-Boot

在開機這個過程中，TF-A 要幫助我們做電源控制與多核心啟動（PSCI），Orange Pi Zero 3 有 4 顆核心（Cortex-A53），通電開機時，只有 Core 0 會醒來執行程式，另外三顆核心（Core 1~3）都在休眠。

在 ARMv8 架構下，OS 是沒有權限直接把其他 core 叫醒的，需要依靠 TF-A。

因此，TF-A 就像是我們的硬體管家。

:::success
現在，我們必須寫一個 bash 腳本幫我們打包 TF-A 與 U-boot 的相關檔案。
:::

#### build_uboot.sh

```bash=
#!/usr/bin/env bash
set -euo pipefail

UBOOT_VERSION=v2026.07
TFA_VERSION=v2.14.0
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
JOBS=$(nproc)
```

一開始，我們先指定好要下載的 U-Boot 與 TF-A 版本。

另外將交叉編譯的指令前綴儲存下來，預設使用 ARM64 架構的編譯器。`JOBS` 會透過 `nproc` 自動抓取電腦的 CPU 核心數，如此一來可以多核心平行編譯，能縮短編譯的時間。

:::spoiler 名詞解釋: 交叉編譯 (Cross-Compilation)
*交叉編譯（Cross-Compilation): 指在某一種硬體架構的電腦上，將原始碼編譯成另一種不同硬體架構執行的機器碼。*
:::

由於我們本地的電腦架構與 Orange Pi Zero 3 不一樣，CPU 的指令集不同，用一般的方法編譯的話得到的執行檔是專門給本地的電腦使用，非板子，因為板子是看不懂這些指令集的。

:::info
那為什麼不直接在板子上編譯？

Ans: 板子現在連作業系統都沒有，根本無法執行編譯器來編譯自己。
:::

```bash=
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$ROOT/build
TFA=$BUILD/tf-a
UBOOT=$BUILD/u-boot
```

設定好專案的資料夾結構定位。

---

```bash=
for cmd in git make "${CROSS_COMPILE}gcc" bison flex swig; do
    if ! command -v "$cmd" >/dev/null; then
        echo "error: missing '$cmd'. Install the build dependencies with:" >&2
        echo "  sudo apt install gcc-aarch64-linux-gnu bison flex swig python3-dev \\" >&2
        echo "    python3-setuptools python3-pyelftools libssl-dev libgnutls28-dev uuid-dev" >&2
        exit 1
    fi
done
```
編譯的依賴檢查，缺少某些環境會提示安裝。

---

```bash=
mkdir -p "$BUILD"
[ -d "$TFA" ]   || git clone --depth 1 --branch "$TFA_VERSION" \
    https://github.com/ARM-software/arm-trusted-firmware.git "$TFA"
[ -d "$UBOOT" ] || git clone --depth 1 --branch "$UBOOT_VERSION" \
    https://github.com/u-boot/u-boot.git "$UBOOT"
```

下載原始碼。

---

```bash=
make -C "$TFA" -j"$JOBS" CROSS_COMPILE="$CROSS_COMPILE" PLAT=sun50i_h616 DEBUG=0 bl31
```

編譯 TF-A，`PLAT` 指定目標硬體平台，`DEBUG=0 bl31` 關閉除錯訊息並指定只編譯 BL31 (Bootloader Stage 3-1，即常駐在 EL3 的安全監控層韌體)，最後會產生 `bl31.bin`。

---

```bash=
make -C "$UBOOT" CROSS_COMPILE="$CROSS_COMPILE" orangepi_zero3_defconfig
make -C "$UBOOT" -j"$JOBS" CROSS_COMPILE="$CROSS_COMPILE" \
    BL31="$TFA/build/sun50i_h616/release/bl31.bin" SCP=/dev/null
    
echo
echo "done: $UBOOT/u-boot-sunxi-with-spl.bin"
```

編譯 U-boot 並打包，最後得到 `u-boot-sunxi-with-spl.bin`。

這裡面已經包含 `eGON`、`SPL`、`TF-A` 以及 `U-Boot` 的本體。

:::spoiler 名詞解釋: eGON
eGON 是一段 32 bytes 的 header，在 Orange Pi 通電的瞬間，BROM 會找到 SD 卡第 16 個 sector (8KB) 的位置，檢查前 32 個位元組有沒有符合格式的規定。

eGON 會告訴 CPU 真正的程式碼要從哪開始，另外也會檢查 Magic String 與 Checksum，確定沒問題後才會准許開機。

可以理解為是晶片專屬的防偽標籤與通行證。
:::

最後，我們回顧一下我們的 `u-boot-sunxi-with-spl.bin`

```
[檔案最開頭, 第 0 Byte]
 ├─ eGON Header (32 Bytes，含有 "eGON.BT0" 字串)
 │
 ├─ SPL 程式碼 (約 30 KB，負責喚醒 DRAM)
 │
[中間填充空白對齊]
 │
 ├─ TF-A (BL31，常駐 EL3 的安全管家)
 │
 └─ U-Boot 本體 (龐大的主程式，提供命令列與載入 Kernel 的能力)
```

（BROM $\rightarrow$ SPL $\rightarrow$ TF-A $\rightarrow$ U-Boot）

如此一來，就完成了第一步驟！

下一步，我們要將這份開機的程序放進 SD 卡中。