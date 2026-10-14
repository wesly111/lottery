# 即時抽籤系統：GitHub Pages + Supabase

## 特色
- **抽順序**：管理員設定 N 人，自動產生 1～N，抽後不放回。
- **分配組別**：管理員設定各組名稱與名額，依名額產生籤，抽後不放回。
- **同一個管理後台**：切換模式、編輯、儲存、開放、暫停、新一輪。
- **兩個公開網址**：`/` 為抽籤端，`/admin.html` 為管理端。後台須登入。
- **即時同步**：Realtime 訂閱 + 每 12 秒備援刷新。
- **並發安全**：資料庫函式鎖定抽籤狀態，避免同一張籤被兩人抽走。

## 部署步驟
1. 在 [Supabase](https://supabase.com/dashboard) 建立 Project。
2. 到 **SQL Editor** 執行 `setup.sql`。如果 Realtime publication 已包含該表，最後一行 `alter publication ...` 可跳過。
3. 到 **Authentication > Users** 建立管理員（Email + Password）；記下該帳號 UUID。
4. 在 SQL Editor 執行：`insert into public.lottery_admins(user_id) values ('你的管理員UUID');`
5. 到 **Project Settings > API** 取得 Project URL 與 **publishable key**（或舊版 anon key），填入 `config.js`。**絕對不可放 service_role / secret key**。
6. 在 GitHub 建立公開 repository（例如 `lottery`），將專案根目錄的 HTML、CSS、JS 檔案上傳。`setup.sql` 不必上傳；若上傳也不包含秘密。
7. GitHub repo → Settings → Pages → Deploy from a branch → `main` / `(root)` → Save。
8. 抽籤端：`https://你的帳號.github.io/lottery/`；管理端：`https://你的帳號.github.io/lottery/admin.html`。
9. 第一次登入管理端，先選模式並按 **儲存設定**，再按 **開放抽籤**。管理員可以隨時暫停；已經有人抽過後，若要改名額，須 **建立新一輪**。

## 重要限制
- 公開抽籤端無須登入，透過瀏覽器 localStorage 保存 UUID。這能避免**同一瀏覽器識別碼**在同一輪重抽，但**無法保證每個真實人只能抽一次**（換瀏覽器或清除儲存即可再抽）。若需要嚴格每人一次，請擴充參與者登入或管理員發放一次性憑證。
- 目前任何人都能看見剩餘張數，但只有管理員可查詢完整抽籤紀錄。
- 組別模式的每張籤結果是組名，資料庫會保留重複組名的多張籤，因此每組名額精確。
- 按「儲存設定」或「建立新一輪」都會重建籤池並清除本輪結果。若本輪已有人抽籤，必須用「建立新一輪」且會要求確認。
- 管理員可以公開分享管理端網址，但只有 `lottery_admins` 表中的已登入帳號能修改資料。
- 如需真正即時同步，請確認 Supabase Realtime 已啟用 `lottery_state`；即使 Realtime 連線暫時中斷，頁面每 12 秒也會刷新。

## 檔案
- `index.html`, `participant.js`：抽籤端
- `admin.html`, `admin.js`：管理端
- `common.js`, `config.js`, `style.css`：共用檔案
- `setup.sql`：資料表、RLS、抽籤函式、管理員驗證
