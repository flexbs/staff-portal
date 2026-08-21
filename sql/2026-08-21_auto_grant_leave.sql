-- ============================================================
-- 有給自動付与の恒久対策
-- フレックスビジネスサービス(株) 派遣事業管理プロジェクト
-- 作成日:2026年8月21日 / Claude Codeでレビュー・修正
--
-- 【このファイルについて】
-- 若松さんの引継ぎノートに添付されたSQL草案を、実行前にレビューし、
-- 2件の重大なバグを修正したうえでリポジトリにコードとして保存したもの。
-- 実行はSupabase SQL Editor(推奨・これまでの運用と同じ手順)、
-- または DB接続情報を共有いただければ Claude Code から直接実行も可能。
-- 実行前に必ずSTEP 6のプレビューSELECTを実行し、若松さんの目視確認を
-- 経てから本番反映すること(これまでの運用方針と同じ)。
--
-- 【草案からの変更点(重要・要確認)】
--
-- 1. 重大バグ①:同じ月内に毎日重複INSERTされる問題
--    草案は months_service(=経過月数)が 6,18,30... と「一致するか」だけを
--    毎日チェックしていたが、months_service は AGE() の月部分だけを取り出す
--    実装のため、対象月の間ずっと(約30日間)条件がtrueのままになる。
--    pg_cronで毎日実行すると、同じ人に同じ節目の付与が30回前後
--    重複INSERTされてしまう(有給残が実態と大きくズレる致命的な不具合)。
--    → 対策:対象者ごとに「今どの節目に到達しているか」を計算した上で、
--      その節目の対象日(target_date)を基準に ±の許容ウィンドウ内でのみ
--      判定し、かつ同じウィンドウ内に既存のleave_grants行がないかを
--      EXISTSで確認してから初めてINSERTするよう変更(冪等化)。
--
-- 2. 重大バグ②:remaining_daysのマイナス相殺ロジックが二重減算になる
--    草案は staffs.paid_leave_remaining がマイナス(先出し/有給残が
--    足りないまま承認された状態。実際にこの警告機能が2026年に追加済み)の
--    場合、新規付与行の remaining_days を「付与日数 + 現在のマイナス残」に
--    縮めていた。しかし update_paid_leave_remaining() は各leave_grants行の
--    remaining_days を単純合算していると考えられ、その場合は既存のマイナス
--    残行はそのまま残るため、新規行だけ縮めると合計が二重に減ってしまう
--    (本来 20-3=17 になるべきところ、17-3=14 と誤って計算される)。
--    → 対策:新規付与行は常に remaining_days = grant_days_calc とし、
--      特別な相殺処理をしない(合算時に自然に正しく相殺されるため)。
--    ※ このロジックの前提(update_paid_leave_remaining()が単純SUMである
--      こと)はClaude Codeからは関数定義を直接確認できていないため、
--      本番反映前に一度その関数定義を確認しておくことを推奨。
--
-- 3. 冪等性:関数を手動で複数回実行しても重複INSERTされないよう、
--    EXISTS判定を追加(草案にはこの安全装置がなかった)。
--
-- 4. grant_days_calc=0(想定外のweekly_working_days値)の場合は
--    INSERTせず、RAISE WARNINGでログに残すよう変更(ゴミ行を作らないため)。
--
-- STEP 1〜3(列追加・hire_date一括更新・weekly_working_days設定)は
-- 若松さんの引継ぎノートに記載の草案から内容の変更なし(71名・9名分、
-- 確認済みのデータをそのまま採用)。
-- ============================================================


-- ============================================================
-- STEP 1: staffsテーブルへの列追加
-- ============================================================

ALTER TABLE staffs ADD COLUMN IF NOT EXISTS hire_date DATE;
COMMENT ON COLUMN staffs.hire_date IS '正しい入社日(⑤スタッフマスターより)。dispatch_start_dateとは別物、有給計算はこちらを使う';

ALTER TABLE staffs ADD COLUMN IF NOT EXISTS weekly_working_days INTEGER;
COMMENT ON COLUMN staffs.weekly_working_days IS '週所定労働日数。標準対象者はNULL(フル勤務扱い)。比例付与対象者のみ1〜4を設定';


-- ============================================================
-- STEP 2: hire_dateの一括更新(2026/8/18時点の⑤スタッフマスター 71名分)
-- ============================================================
-- 実行前に必ずSELECTで現状を確認し、若松さんの目視確認を経てから実行してください。

UPDATE staffs SET hire_date = '2024-09-02' WHERE employee_id = '1007'; -- 安達亜希子
UPDATE staffs SET hire_date = '2005-07-25' WHERE employee_id = '1040'; -- 伊藤竜也
UPDATE staffs SET hire_date = '2018-03-29' WHERE employee_id = '1042'; -- 稲田美紀
UPDATE staffs SET hire_date = '2025-07-28' WHERE employee_id = '1143'; -- 岡村真人
UPDATE staffs SET hire_date = '2011-05-23' WHERE employee_id = '1105'; -- 尾上知佳
UPDATE staffs SET hire_date = '2018-07-01' WHERE employee_id = '3044'; -- 片倉早紀
UPDATE staffs SET hire_date = '2025-03-20' WHERE employee_id = '2019'; -- 角屋克博
UPDATE staffs SET hire_date = '2005-05-30' WHERE employee_id = '2024'; -- 川井さおり
UPDATE staffs SET hire_date = '2022-05-01' WHERE employee_id = '2102'; -- 川本せりあ
UPDATE staffs SET hire_date = '2021-04-19' WHERE employee_id = '2098'; -- 久保理絵
UPDATE staffs SET hire_date = '2016-08-01' WHERE employee_id = '2091'; -- 近藤真美
UPDATE staffs SET hire_date = '2013-06-04' WHERE employee_id = '3004'; -- 境妙
UPDATE staffs SET hire_date = '2002-09-01' WHERE employee_id = '3048'; -- 末武真奈美
UPDATE staffs SET hire_date = '2018-01-25' WHERE employee_id = '3053'; -- 杉野亜由美
UPDATE staffs SET hire_date = '2025-06-01' WHERE employee_id = '3079'; -- 諏訪聡子
UPDATE staffs SET hire_date = '2020-07-06' WHERE employee_id = '1120'; -- 相原かおり(単発要員・有給対象外)
UPDATE staffs SET hire_date = '2024-09-02' WHERE employee_id = '4108'; -- 田中穂乃香
UPDATE staffs SET hire_date = '2022-01-21' WHERE employee_id = '4063'; -- 土屋和美
UPDATE staffs SET hire_date = '2026-04-16' WHERE employee_id = '4113'; -- 東矢ひろみ
UPDATE staffs SET hire_date = '2026-02-16' WHERE employee_id = '4111'; -- 外池宏次
UPDATE staffs SET hire_date = '2016-12-21' WHERE employee_id = '5008'; -- 中島一雄(特殊対応・自動化対象外)
UPDATE staffs SET hire_date = '2004-03-01' WHERE employee_id = '5013'; -- 中嶋美幸
UPDATE staffs SET hire_date = '2023-08-16' WHERE employee_id = '5074'; -- 中山由美
UPDATE staffs SET hire_date = '2011-03-29' WHERE employee_id = '5040'; -- 西嶋大輔
UPDATE staffs SET hire_date = '2024-11-21' WHERE employee_id = '5079'; -- 西山愛
UPDATE staffs SET hire_date = '2025-05-01' WHERE employee_id = '5080'; -- 納冨悠希
UPDATE staffs SET hire_date = '2026-01-13' WHERE employee_id = '6113'; -- 濵田友華
UPDATE staffs SET hire_date = '2016-03-07' WHERE employee_id = '6018'; -- 早高祥子
UPDATE staffs SET hire_date = '2005-03-07' WHERE employee_id = '6032'; -- 樋口聡明
UPDATE staffs SET hire_date = '2022-02-01' WHERE employee_id = '6103'; -- 平田愛
UPDATE staffs SET hire_date = '2025-01-14' WHERE employee_id = '6111'; -- 渕上秋美
UPDATE staffs SET hire_date = '2024-12-16' WHERE employee_id = '6094'; -- 細川浩一
UPDATE staffs SET hire_date = '2021-02-17' WHERE employee_id = '6100'; -- 堀英人
UPDATE staffs SET hire_date = '2002-05-17' WHERE employee_id = '7036'; -- 溝上祥代
UPDATE staffs SET hire_date = '2025-01-16' WHERE employee_id = '7083'; -- 三岳直子
UPDATE staffs SET hire_date = '2023-06-06' WHERE employee_id = '7089'; -- 本村晴美
UPDATE staffs SET hire_date = '2020-01-06' WHERE employee_id = '7075'; -- 森岡純子
UPDATE staffs SET hire_date = '2024-12-01' WHERE employee_id = '7092'; -- 森下結
UPDATE staffs SET hire_date = '2025-04-21' WHERE employee_id = '8073'; -- 大和晴菜
UPDATE staffs SET hire_date = '2025-11-01' WHERE employee_id = '1148'; -- 岩本茉子
UPDATE staffs SET hire_date = '2017-02-21' WHERE employee_id = '1073'; -- 瓜生祥子
UPDATE staffs SET hire_date = '2016-08-18' WHERE employee_id = '1072'; -- 瓜生純子
UPDATE staffs SET hire_date = '2016-05-06' WHERE employee_id = '5050'; -- 江口恵美
UPDATE staffs SET hire_date = '2025-05-01' WHERE employee_id = '1142'; -- 榎並佳織
UPDATE staffs SET hire_date = '2023-10-01' WHERE employee_id = '1136'; -- 大田司
UPDATE staffs SET hire_date = '2016-08-10' WHERE employee_id = '2068'; -- 黒木良太
UPDATE staffs SET hire_date = '2026-04-01' WHERE employee_id = '3080'; -- 坂田萌子
UPDATE staffs SET hire_date = '2011-07-13' WHERE employee_id = '3015'; -- 坂本夏子
UPDATE staffs SET hire_date = '2022-05-09' WHERE employee_id = '3071'; -- 佐多薫
UPDATE staffs SET hire_date = '2018-09-03' WHERE employee_id = '3022'; -- 佐藤正治
UPDATE staffs SET hire_date = '2010-08-27' WHERE employee_id = '3031'; -- 柴田絵理
UPDATE staffs SET hire_date = '2016-09-20' WHERE employee_id = '3060'; -- 善明弘美
UPDATE staffs SET hire_date = '2026-04-01' WHERE employee_id = '4097'; -- 武部将士
UPDATE staffs SET hire_date = '2026-04-01' WHERE employee_id = '4112'; -- 田中理恵
UPDATE staffs SET hire_date = '2023-09-14' WHERE employee_id = '8071'; -- 中川萌
UPDATE staffs SET hire_date = '2023-01-10' WHERE employee_id = '1130'; -- 中西直子
UPDATE staffs SET hire_date = '2008-04-07' WHERE employee_id = '5017'; -- 長島弘子
UPDATE staffs SET hire_date = '2010-06-01' WHERE employee_id = '7002'; -- 前川亜理沙
UPDATE staffs SET hire_date = '2025-02-04' WHERE employee_id = '7093'; -- 満田望
UPDATE staffs SET hire_date = '2026-01-29' WHERE employee_id = '8075'; -- 山口茉都香
UPDATE staffs SET hire_date = '2018-03-21' WHERE employee_id = '8038'; -- 吉田貴司
UPDATE staffs SET hire_date = '2024-03-01' WHERE employee_id = '9012'; -- 渡邊淳
UPDATE staffs SET hire_date = '2015-04-23' WHERE employee_id = '2023'; -- 池田純香
UPDATE staffs SET hire_date = '2005-02-10' WHERE employee_id = '2037'; -- 河東奈津子
UPDATE staffs SET hire_date = '2026-07-01' WHERE employee_id = '3081'; -- 菅原彩乃
UPDATE staffs SET hire_date = '2026-08-17' WHERE employee_id = '3082'; -- 下川舞優
UPDATE staffs SET hire_date = '2026-08-17' WHERE employee_id = '4096'; -- 高田圭江
UPDATE staffs SET hire_date = '2026-08-17' WHERE employee_id = '5045'; -- 西山彩
UPDATE staffs SET hire_date = '2026-07-01' WHERE employee_id = '1149'; -- 今村千絵
UPDATE staffs SET hire_date = '2026-07-13' WHERE employee_id = '8076'; -- 山本楓
UPDATE staffs SET hire_date = '2026-08-17' WHERE employee_id = '5081'; -- 西原あゆみ


-- ============================================================
-- STEP 3: weekly_working_daysの設定(比例付与9名)
-- ============================================================

UPDATE staffs SET weekly_working_days = 4 WHERE employee_id = '1149'; -- 今村千絵
UPDATE staffs SET weekly_working_days = 4 WHERE employee_id = '1142'; -- 榎並佳織
UPDATE staffs SET weekly_working_days = 3 WHERE employee_id = '1136'; -- 大田司
UPDATE staffs SET weekly_working_days = 4 WHERE employee_id = '1143'; -- 岡村真人
UPDATE staffs SET weekly_working_days = 3 WHERE employee_id = '2098'; -- 久保理絵
UPDATE staffs SET weekly_working_days = 3 WHERE employee_id = '4108'; -- 田中穂乃香
UPDATE staffs SET weekly_working_days = 2 WHERE employee_id = '7083'; -- 三岳直子
UPDATE staffs SET weekly_working_days = 3 WHERE employee_id = '7093'; -- 満田望

-- 中島一雄(employee_id = '5008') = 4日/週
-- ※2026/6/1に週4日→週5日に変更、2027/6/21の付与から日数体系が変わる特殊ケース。
-- 自動化対象から除外し、2027/6/21のタイミングで手動対応する方針(ノート記載の通り)。
-- 参考値としてweekly_working_daysは設定しておくが、STEP4の関数内で
-- employee_id = '5008' を明示的に除外している。
UPDATE staffs SET weekly_working_days = 4 WHERE employee_id = '5008'; -- 中島一雄(自動化対象外)


-- ============================================================
-- STEP 4: 自動付与関数の作成(草案から2件のバグを修正)
-- ============================================================
-- 前提:
--  - status NOT IN ('契約終了','管理者','短期・単発') を有給付与の対象とする
--    (若松さん確認済み:短期・単発は除外、請負は対象。2026/8/21時点で
--     短期・単発に該当するのは高田圭江・相原かおり・西山彩の3名だが、
--     今後増減する前提でハードコードせずstatus列で判定)
--  - 標準テーブル: 6ヶ月=10日,1年6ヶ月=11日,2年6ヶ月=12日,
--                  3年6ヶ月=14日,4年6ヶ月=16日,5年6ヶ月=18日,
--                  6年6ヶ月以降=20日(以降ずっと20日)
--  - 比例付与の法定表(週所定労働日数別、ノート記載の表と同じ)
--  - 節目(1〜6番目=6,18,30,42,54,66ヶ月、7番目以降は12ヶ月おき)ごとに
--    「対象日(target_date)の前後一定期間内」で、かつ同じ期間に該当する
--    leave_grants行がまだ無い場合のみ1回だけINSERTする(冪等・重複防止)
--  - 許容ウィンドウは target_date の10日前 〜 30日後とする
--    (紙カード確認により、実際の付与日が計算日と数日ズレることがある
--     [教訓㉔]ことと、pg_cronが数日〜数週間止まっても取りこぼさない
--     ことの両方に対応するため)
--  - expire_dateは生成列のためINSERT文に含めない(教訓㉗)

CREATE OR REPLACE FUNCTION auto_grant_leave() RETURNS void
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r RECORD;
  months_service INT;
  current_milestone INT;
  target_date DATE;
  grant_days_calc INT;
  already_granted BOOLEAN;
BEGIN
  FOR r IN
    SELECT
      s.id AS staff_id,
      s.employee_id,
      s.hire_date,
      s.weekly_working_days
    FROM staffs s
    WHERE s.hire_date IS NOT NULL
      AND s.status NOT IN ('契約終了', '管理者', '短期・単発')  -- 若松さん確認済み:短期・単発は除外、請負は対象
      AND s.employee_id <> '5008'  -- 中島一雄さんは特殊対応のため自動化対象から除外
  LOOP
    -- 入社日からの経過月数(完了した月数)
    months_service := (
      DATE_PART('year', AGE(CURRENT_DATE, r.hire_date)) * 12
      + DATE_PART('month', AGE(CURRENT_DATE, r.hire_date))
    )::INT;

    IF months_service < 6 THEN
      CONTINUE;  -- まだ最初の付与(6ヶ月)前
    END IF;

    -- 現在到達している最新の節目番号(1=6ヶ月, 2=1年6ヶ月, ...)
    current_milestone := FLOOR((months_service - 6) / 12)::INT + 1;

    -- その節目の本来の対象日
    target_date := r.hire_date + ((6 + 12 * (current_milestone - 1)) || ' months')::INTERVAL;

    -- 対象日から30日以上経過している場合は、今回の自動実行では対象外
    -- (取りこぼした場合は、これまで通り紙カード等での棚卸しで手当てする)
    IF CURRENT_DATE > target_date + INTERVAL '30 days' THEN
      CONTINUE;
    END IF;
    IF CURRENT_DATE < target_date - INTERVAL '10 days' THEN
      CONTINUE;
    END IF;

    -- 既にこの節目分が記録済みかどうか(手動追加・過去の自動実行の両方を考慮)
    SELECT EXISTS (
      SELECT 1 FROM leave_grants g
      WHERE g.staff_id = r.staff_id
        AND g.grant_date BETWEEN target_date - INTERVAL '10 days' AND target_date + INTERVAL '30 days'
    ) INTO already_granted;

    IF already_granted THEN
      CONTINUE;
    END IF;

    -- 付与日数の決定(標準 or 比例)
    IF r.weekly_working_days IS NULL THEN
      grant_days_calc := CASE current_milestone
        WHEN 1 THEN 10 WHEN 2 THEN 11 WHEN 3 THEN 12
        WHEN 4 THEN 14 WHEN 5 THEN 16 WHEN 6 THEN 18
        ELSE 20 END;
    ELSIF r.weekly_working_days = 4 THEN
      grant_days_calc := CASE current_milestone
        WHEN 1 THEN 7 WHEN 2 THEN 8 WHEN 3 THEN 9
        WHEN 4 THEN 10 WHEN 5 THEN 12 WHEN 6 THEN 13
        ELSE 15 END;
    ELSIF r.weekly_working_days = 3 THEN
      grant_days_calc := CASE current_milestone
        WHEN 1 THEN 5 WHEN 2 THEN 6 WHEN 3 THEN 6
        WHEN 4 THEN 8 WHEN 5 THEN 9 WHEN 6 THEN 10
        ELSE 11 END;
    ELSIF r.weekly_working_days = 2 THEN
      grant_days_calc := CASE current_milestone
        WHEN 1 THEN 3 WHEN 2 THEN 4 WHEN 3 THEN 4
        WHEN 4 THEN 5 WHEN 5 THEN 6 WHEN 6 THEN 6
        ELSE 7 END;
    ELSIF r.weekly_working_days = 1 THEN
      grant_days_calc := CASE current_milestone
        WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 2
        WHEN 4 THEN 2 WHEN 5 THEN 3 WHEN 6 THEN 3
        ELSE 3 END;
    ELSE
      grant_days_calc := 0;
      RAISE WARNING 'auto_grant_leave: 想定外のweekly_working_days=% (employee_id=%)。スキップしました', r.weekly_working_days, r.employee_id;
    END IF;

    IF grant_days_calc > 0 THEN
      -- remaining_daysは常に付与日数そのまま。マイナス残(先出し)との相殺は
      -- update_paid_leave_remaining()側の単純合算で自然に行われるため、
      -- ここで縮める必要はない(縮めると二重減算になる。上部コメント参照)
      INSERT INTO leave_grants (staff_id, grant_date, grant_days, remaining_days)
      VALUES (r.staff_id, target_date, grant_days_calc, grant_days_calc);
    END IF;

  END LOOP;
END;
$$;


-- ============================================================
-- STEP 5: pg_cronでの毎日自動実行スケジュール設定
-- ============================================================
-- update_paid_leave_remaining()が毎日20時に実行されているため、
-- その前(19時)に自動付与を実行し、20時の集計に反映させる想定

SELECT cron.schedule(
  'auto_grant_leave_daily',
  '0 19 * * *',
  $$SELECT auto_grant_leave();$$
);


-- ============================================================
-- STEP 6: 動作確認用(本番反映前に必ず実行)
-- ============================================================
-- 6-a. 今日時点で「節目の対象日から30日以内」に該当し、かつ
--      まだ記録が無い(=このデプロイで実際にINSERTされる見込みの)人を確認する
-- SELECT
--   s.employee_id, s.hire_date, s.weekly_working_days, s.status,
--   (DATE_PART('year', AGE(CURRENT_DATE, s.hire_date)) * 12
--    + DATE_PART('month', AGE(CURRENT_DATE, s.hire_date)))::INT AS months_service
-- FROM staffs s
-- WHERE s.hire_date IS NOT NULL
--   AND s.status NOT IN ('契約終了','管理者','短期・単発')
--   AND s.employee_id <> '5008';
--
-- 6-b. 上記で対象になりそうな人がいれば、まずauto_grant_leave()を試験実行し、
--      leave_grantsに想定通りの行が追加されるか確認してからstaffs.paid_leave_remaining
--      への反映(update_paid_leave_remaining()実行)を確認する
-- SELECT auto_grant_leave();
-- SELECT * FROM leave_grants WHERE grant_date >= CURRENT_DATE - INTERVAL '1 day' ORDER BY id DESC;
