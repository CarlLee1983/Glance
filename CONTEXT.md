# Glance — 領域詞彙表

> 這份檔案只是**詞彙表**:記錄領域用語的正式定義,不放實作細節、不當規格書。
> 決策紀錄見 `docs/DECISIONS.md` 與 `docs/adr/`。

## 記憶體排行(Memory Apps)

### 出身(Kind)
一列記憶體用量的**執行檔住在哪**,純由路徑字串判定,**不涉及**能不能結束它。
是給使用者「這是什麼東西」的線索,不是「我能不能動它」的答案。共五類:

- **App** — 頂層 `.app`(路徑中恰有一個 `.app` 元件)。
- **App 子行程(App Child)** — 巢狀在另一個 `.app` 內的 helper(路徑中 `.app` 出現多於一次),例如 Chrome 的 Renderer。隨母體 App 一起結束,不單獨結束。
- **系統服務(System Service)** — Apple 系統目錄下的服務 / daemon(`/System/`、`/usr/sbin/`、`/usr/libexec/`、`/sbin/`、`/Library/Apple/`)。
- **背景程式(User Process)** — 有執行檔、但既非 app 也不在 Apple 系統目錄的其餘行程。涵蓋命令列工具(`node`、`zsh`)與第三方 daemon(`ovpnagent`)。**刻意不宣稱是「命令列」**,因為這是一個「剩餘集合」而非單一類別。
- **未知來源(Unknown)** — 取不到執行檔路徑。

### 可處置性(Terminability)
與「出身」**正交**的另一條線:這一列能不能被使用者單獨結束。
判準是「此 bundle 是否登記在 `NSWorkspace.runningApplications` 裡」——與實際執行結束用的是**同一套 matcher**,所以「看得到結束鈕」等於「按得動」。出身是 App 但不在 running apps 裡的(如 App 子行程)不可結束。

### 聚合鍵(Group Key)
把多個行程歸為一列的身分依據:
- App / App 子行程 → 所屬 `.app` 的 bundle 路徑。
- 其他有路徑的行程 → **執行檔路徑**(同路徑即同一程式的多個實例,予以加總)。
- 取不到路徑 → 退回行程名。

> 關鍵:app 與非 app 用**同一套「同身分即加總」規則**。不同路徑永遠不會被誤加總。

### 落單行程 PID(Solo PID)
只有**單一行程**的群組才有可指認的 pid,供指認 / 複製診斷用。多行程群組沒有單一 pid(交由 row 展開查明細),此值為 `nil`。
