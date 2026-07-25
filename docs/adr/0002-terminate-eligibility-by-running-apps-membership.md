# 結束鈕以 running-apps 成員資格為準

記憶體排行的「結束高佔用 App」鈕,原本以 `bundleURL != nil`(有 .app 包)決定是否顯示。我們改為以「此 bundle 是否登記在 `NSWorkspace.runningApplications` 裡」為準,復用實際結束時所用的同一套 `AppTerminationMatcher`。

**為什麼:** 舊判準會對「有 .app 包、但不在 running apps 裡」的列長出一顆按了沒反應的鈕。最典型的是 Chrome Helper (Renderer)——它是記憶體榜首、有自己的巢狀 `.app`,但 LaunchServices 不登記它;使用者按下結束、再按確認,`terminateApp` 比不到對象回傳 0,舊程式碼把這個結構性失敗誤當成「競態」而靜默,畫面毫無回饋。用同一套 matcher 決定「顯示鈕」與「執行結束」,「看得到就按得動」才會為真。

**取捨與後果:** `eligible()` 從純字串比較變成會呼叫 AppKit,但只在 hover 當下對單一列評估一次(短路),成本可忽略。判斷邏輯留在 `AppTerminationMatcher`(GlanceCore、純函式、可測),只有列舉 running apps 的 AppKit 呼叫落在 GlanceApp,符合「Keep GlanceCore UI-Free」。`count == 0` 的靜默保留,語意從「掩蓋 bug」轉為「兜底真正的競態」。
