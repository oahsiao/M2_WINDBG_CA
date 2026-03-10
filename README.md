# WinDbg Autonomous Root Cause Investigation Engine

> **GitHub Copilot Instructions for Kernel Dump Analysis**  
> Version 2.1 · 繁體中文溝通 · Evidence-Driven · Story-First

---

## 這是什麼

這是一份 `.github/instructions` 設定檔，讓 GitHub Copilot agent 化身為 **Microsoft CSS Level-4 Kernel Escalation Engineer**，能夠自主分析 Windows kernel memory dump（MEMORY.DMP），並產出完整的根因報告。

AI 的定位不是「指令執行者」，而是「因果推理者」——它會像真正的 CSS 工程師一樣，從證據推導根因，說出完整的故事：

> **什麼事情發生了 → 為什麼發生 → 為什麼系統沒有自救**

---

## 使用方式

### 1. 放置檔案

將 instructions 檔案放入你的 repo：

```
your-repo/
└── .github/
    └── instructions/
        └── windbg-kernel-debugger.instructions.md
```

### 2. 確認環境

| 項目 | 路徑 |
|---|---|
| Debugger | `C:\Program Files\WindowsApps\Microsoft.WinDbg.Slow_...\amd64\cdb.exe` |
| Dump | `D:\TEMP\WINDBG\ERIC\MEMORY.DMP` |
| Symbol Cache | `C:\symbols` |
| 輸出目錄 | dump 所在目錄（自動寫入） |

> Symbol path 已預設包含 Microsoft public symbol server 及內部 `\\desmo` 路徑，**請勿修改**。



### 3 Debugger路徑

WINDBG.NEXT 才有支援 http://symweb. 每台主機安裝路徑可能不同. 通過下面方式找到路徑

```
Powershell 
指令
(Get-AppxPackage Microsoft.WinDbg.Fast).InstallLocation + "\WinDbgX.exe"
PS C:\Users\b-jehsia> (Get-AppxPackage Microsoft.WinDbg.Fast).InstallLocation + "\WinDbgX.exe"
C:\Program Files\WindowsApps\Microsoft.WinDbg.Fast_1.2602.5002.0_x64__8wekyb3d8bbwe\WinDbgX.exe

(Get-AppxPackage Microsoft.WinDbg.Slow).InstallLocation + "\WinDbgX.exe"
PS C:\WINDOWS\system32> (Get-AppxPackage Microsoft.WinDbg.Slow).InstallLocation + "\WinDbgX.exe"
C:\Program Files\WindowsApps\Microsoft.WinDbg.Slow_1.2601.12001.1_x64__8wekyb3d8bbwe\WinDbgX.exe

```

選一個 你要使用的 WINDBG NEXT , 路徑要做個加工 再放到Prompt
C:\Program Files\WindowsApps\Microsoft.WinDbg.Fast_1.2602.5002.0_x64__8wekyb3d8bbwe\ `amd64\cdb.exe`

C:\Program Files\WindowsApps\Microsoft.WinDbg.Slow_1.2601.12001.1_x64__8wekyb3d8bbwe\ `amd64\cdb.exe`



### 4. 啟動分析

開啟 Copilot agent，讓它開始執行。完成 Phase 0 驗證後，它會暫停並等待你輸入：

```
GO
```

確認沒問題後輸入 GO，agent 即開始自主完成所有 Phase。

---

## 分析流程總覽

```
PHASE 0   環境驗證 & Dump 類型判定
    ↓  ← 等待使用者輸入 "GO"
PHASE 1   失敗分類 & 調查路徑路由
    ↓  ← Fast Path 判斷（答案已知則跳至 Phase 3）
PHASE 2   系統基線收集（依分類選擇指令）
    ↓
PHASE 3   Wait Chain 重建（含循環偵測 & Priority Inversion 偵測）
    ↓
PHASE 4   Hang 時間線重建（Evidence Backward 方法）
    ↓
PHASE 5   假設驅動指令生成（逐一假設 → 執行 → 驗證）
    ↓
PHASE 6   Driver 嫌疑分數引擎（加分 + 減分 + 分類）
    ↓
PHASE 7   多 Dump 關聯分析（若同目錄有多個 .dmp）
    ↓
PHASE 8   根因宣告（一句話 + 短鏈 + 詳細因果 + 排除說明 + 信心分數）
    ↓
PHASE 9   Driver Verifier 計畫 & 後續偵錯建議（score ≥ 70 觸發）
```

每個 Phase 都有明確的**目的**、**輸出格式**，以及根據 dump 類型的**條件指令選擇**。

---

## 核心能力

### 失敗類型分類（10 種）

| 類型 | 觸發條件 |
|---|---|
| `HANG` | 系統無回應，無 bugcheck |
| `DEADLOCK` | 兩個以上 thread 互相等待 |
| `DPC_STARVATION` | `0x133` / DPC watchdog timeout |
| `ISR_STORM` | IRQL 長時間在 DIRQL 以上 |
| `POWER_IRP_BLOCK` | IRP 卡在電源狀態轉換 |
| `GPU_TIMEOUT` | `0x116` / `0x117` TDR timeout |
| `STORAGE_TIMEOUT` | storport / disk IRP 無回應 |
| `MEMORY_CORRUPTION` | `0x50` / `0xC5` / `0x1A` 等 |
| `FILESYSTEM_HANG` | NTFS / MUP / filter hang |
| `UNKNOWN` | 走完完整基線收集再判斷 |

分類確定後，系統會自動路由到對應的調查指令集，跳過無關指令，節省配額。

---

### Wait Chain 重建（Phase 3）

這是整個分析的核心。系統會逐層展開等待關係，直到找到 Root Blocker：

```
[BLOCKED THREAD A]  TID=xxxx  Priority=12  WaitTime=38s
  waiting on → [OBJECT X: Mutex @ 0xFFFF...]
                 owned by → [THREAD B]  TID=yyyy  Priority=8  ← Priority Inversion!
                               waiting on → [OBJECT Y: Event @ 0xFFFF...]
                                              owner=NONE / external event  ← ROOT BLOCKER
```

**兩個自動偵測機制：**

- **循環死鎖偵測（Visited Set）**：A→B→C→A 的 circular deadlock 會被自動識別，不會無限循環
- **Priority Inversion 偵測**：owner 優先級低於 waiter 優先級時自動標記，這是常被忽略的根因

---

### ASCII 記憶體指紋分析（附錄 B）

這是這份 instructions 的獨特能力，源自實戰經驗。

**核心概念：** Windows kernel 的每一個記憶體 allocation 都帶有 4-byte Pool Tag。即使 symbols 完全缺失、pool header 已損毀、stack 無法解析，`db` 指令輸出右側的 ASCII 欄位仍然可能殘留著指向 guilty driver 的字串指紋。

```
ffff8001`23456780  4e 76 47 72 00 00 00 00-4e 76 53 74 00 00 00 00  NvGr....NvSt....
                                                                      ^^^^
                                                              Pool Tag: NvGr → nvlddmkm.sys (NVIDIA)
```

**會自動觸發的情況：**
- `FAULTING_MODULE` 是 `nt` 或 `unknown`（通常是受害者，不是根因）
- `!pool` 回傳 corrupted 或 unknown tag
- symbols 缺失，`ln` 無法解析位址
- Wait chain 無法收斂到明確 driver

**可識別的字串類型：**

| 類型 | 範例 | 下一步 |
|---|---|---|
| Pool Tag | `NvGr`, `Stor`, `NtFi` | `!poolfind <tag>` 反查 driver |
| Driver 名稱 | `nvlddmkm`, `storahci` | `lm m` 確認是否已載入 |
| Device Path | `\Device\Harddisk0\DR0` | `!devobj` 確認 driver ownership |
| Registry Path | `\Registry\Machine\...\Services\...` | 確認對應 service |
| 版本字串 | `1.2.3.4567 (built by: ...)` | 識別模組版本 |
| ASSERT 訊息 | `ASSERT failed at line 1234` | 定位原始碼位置 |

每個發現的 artifact 會自動更新 Phase 6 的 Driver Score（最高 +35 分）。

---

### Driver 嫌疑分數引擎（Phase 6）

所有證據都被量化成分數，並區分 driver 的類型：

**加分項目：**

| 因子 | 分數 |
|---|---|
| Blocked stack 最頂層 | +40 |
| 持有 root blocker 的 lock | +35 |
| Pool tag / ASCII artifact 確認 | +35 |
| 長時間執行的 DPC/ISR | +30 |
| 出現在 3+ blocked thread stack | +25 |
| Priority inversion 持有者 | +20 |
| 未回應的 pending IRP | +20 |

**減分項目：**

| 因子 | 分數 |
|---|---|
| 是 `ntoskrnl`（通常是受害者） | −20 |
| Microsoft 簽名 first-party driver | −10 |
| 只被動出現且其他 driver 證據更強 | −15 |

Score ≥ 70 自動觸發 Phase 9（Driver Verifier 建議）。

---

### 根因宣告（Phase 8）

根因輸出被強制分為四層，確保完整性：

```
8-A  一句話根因（英文 + 繁體中文）
8-B  簡短因果鏈（觸發源 → 機制 → 蔓延 → 症狀 → Recovery 失敗）
8-C  詳細因果鏈（觸發點、蔓延機制、Scheduler 影響、Recovery 失敗原因）
8-D  排除說明（哪些假設被排除，以及為什麼）
8-E  信心分數（0–1000）+ 缺口說明
```

**信心分數標準：**

| 分數 | 意義 |
|---|---|
| 850–1000 | 完整證據鏈，Root Blocker 確認，排除說明完整 |
| 650–849 | 強烈指向，有一個環節依賴推斷 |
| 450–649 | 合理假設，多個可能根因 |
| < 450 | 資料不足，先說明缺口再宣告 |

---

## 三份輸出檔案

分析完成後，自動在 dump 所在目錄產出：

| 檔案 | 格式 | 內容 |
|---|---|---|
| `TRACE_<timestamp>.txt` | 純文字 | 完整 debugger session 紀錄，每條指令與完整輸出 |
| `REPORT_<timestamp>.md` | Markdown | 中英雙語故事報告，含時間線、Wait Chain 圖、Driver 排名、後續行動 |
| `EVIDENCE_<timestamp>.json` | JSON | 機器可讀結構化證據，含所有欄位（見下方） |

### EVIDENCE JSON 主要欄位

```
meta                  → dump 類型、engine 版本、指令用量
classification        → 失敗類型
cpu_state             → 失敗 CPU、IRQL、active DPC
blocked_threads       → 每個 blocked thread 的 wait reason、priority、wait time
wait_chain            → 完整等待鏈
circular_deadlock_*   → 循環死鎖偵測結果
root_blocker          → 根源 blocker 的位址、類型、所屬 driver
priority_inversions   → 偵測到的 priority inversion
dpc_state             → DPC starvation 資訊
lock_state            → 每個 lock 的持有者與等待者
irp_state             → pending IRP 清單
driver_scores         → 每個 driver 的分數與證據摘要
ascii_artifacts       → 每個找到的 ASCII 指紋，含 raw bytes 與信心評級
pool_state            → pool corruption 狀態
root_cause            → 完整根因（trigger / propagation / scheduler_impact / recovery_failure_reason）
excluded_hypotheses   → 被排除的假設與原因
symbol_gaps           → 缺失符號及信心影響
recommended_actions   → 後續行動（immediate / if_reproduced / data_to_collect）
```

---

## 安全機制

| 機制 | 說明 |
|---|---|
| 指令配額 | 全程最多 250 條，即時顯示剩餘數量 |
| 調查深度上限 | Wait chain 最深 6 層 |
| Evidence saturation | 連續兩輪無新發現時自動停止 |
| Fast Path | `!analyze -v` 已有答案時直接跳至 Phase 3 |
| 循環偵測 | Visited Set 防止 deadlock chain 無限展開 |
| 分類路由 | 不同失敗類型走不同指令集，不浪費配額 |

---

## 附錄說明

### 附錄 A — 專用分析路徑

針對三種特殊情況的專屬指令集：

- **A1 MEMORY_CORRUPTION**：標準 pool 分析 → ASCII artifact 掃描 → 全記憶體字串搜尋
- **A2 POWER_IRP_BLOCK**：`!poaction` / `!pocaps` / `!irpfind` / `!devnode`，追蹤電源狀態機
- **A3 GPU_TIMEOUT (TDR)**：dxgkrnl / dxgmms2 stacks，區分 timeout vs detected error

### 附錄 B — ASCII 記憶體指紋分析

完整的記憶體字串掃描方法論，包含：
- 5 步驟掃描程序
- 字串辨識優先順序表（Pool Tag → Driver 名稱 → Device Path → ...）
- Pool Tag 快速對照表（14 個常見 tag）
- 標準化 ASCII Artifact 記錄格式
- 與 Driver Score 的整合規則
- 實戰案例說明

### 附錄 C — 符號缺失處理

當 symbols 缺失阻斷調查時，標準化的說明格式，包含：信心影響、繞過嘗試紀錄、以及建議。

---

## 行為守則摘要

```
MUST DO                                     MUST NOT DO
✅ 每條指令先陳述假設                         ❌ 不盲目執行指令
✅ 每個結論引用實際輸出                        ❌ 不把症狀當根因
✅ Wait chain 維護 Visited Set               ❌ 不把 ntoskrnl 列為主要嫌疑
✅ 偵測 priority inversion                   ❌ 信心 < 450 時不宣告根因
✅ Driver scoring 區分三種類型                ❌ 不輸出清單代替故事
✅ 根因包含排除說明                           ❌ symbols 缺失時不放棄，先掃 ASCII
✅ 根因解釋為何無法恢復                        ❌ LOW confidence artifact 不作確定證據
✅ 繁體中文與使用者溝通
✅ 每輪輸出 [LOOP ROUND #N] 狀態
```

---

## 版本紀錄

| 版本 | 主要更新 |
|---|---|
| v1.0 | 初始版本，基本 Phase 0–9 架構 |
| v2.0 | 加入 dump 類型判定、Fast Path、循環偵測、Priority Inversion、Driver Score 減分機制、排除說明、Regression 分析、分類路由 |
| v2.1 | 加入 **ASCII 記憶體指紋分析**（附錄 B）、完整假設庫擴充、EVIDENCE JSON 新增 `ascii_artifacts` 欄位 |
