-- ============================================================
-- 보너스 과제
-- 실행 전 01_schema.sql, 02_sample_data.sql을 먼저 실행할 것
-- ============================================================

PRAGMA foreign_keys = ON;

-- ============================================================
-- [보너스 1] 같은 요구를 JOIN과 서브쿼리 두 방식으로 풀기
-- 요구사항: "댓글이 하나도 달리지 않은 릴스를 찾는다"
-- ============================================================

-- 방식 A: LEFT JOIN + IS NULL
SELECT r.reel_id, r.caption
FROM reels r
LEFT JOIN comments c ON r.reel_id = c.reel_id
WHERE c.comment_id IS NULL;

-- 방식 B: 서브쿼리 NOT IN
SELECT reel_id, caption
FROM reels
WHERE reel_id NOT IN (SELECT DISTINCT reel_id FROM comments);

-- 실행 결과 (샘플 데이터 기준, 두 방식 동일하게 확인됨):
-- (2, '부산 여행 하이라이트')
-- (4, '홈메이드 파스타 daily 레시피')
-- (6, '연습실 daily 비하인드')
-- (9, '게임 speedrun 도전')
-- (13, '수채화 그리기 타임랩스')
--
-- 비교:
-- - LEFT JOIN 방식은 옵티마이저가 조인 후 NULL 필터링을 하므로,
--   결과와 함께 comments 쪽 컬럼도 같이 가져오고 싶을 때 확장하기 쉽다.
-- - 서브쿼리(NOT IN) 방식은 의도(제외 목록)가 코드만 봐도 더 직관적으로 읽히지만,
--   comments.reel_id에 NULL 값이 존재하면 NOT IN 전체가 빈 결과를 반환하는
--   함정이 있다 (이 스키마에서는 reel_id가 NOT NULL이라 안전함).
-- - 데이터 규모가 커지면 일반적으로 LEFT JOIN이 인덱스를 활용하기 더 쉬워
--   성능 면에서 유리한 경우가 많다.


-- ============================================================
-- [보너스 2] 데이터 정합성 깨뜨려 보기
-- 존재하지 않는 user_id(999)를 참조하는 릴스를 강제로 삽입 시도
-- ============================================================

-- 아래 INSERT는 의도적으로 실패해야 하는 테스트 쿼리이다.
-- users 테이블에 user_id = 999인 사용자가 없기 때문에
-- reels.user_id -> users.user_id FK 제약조건에 걸려 삽입이 거부된다.
INSERT INTO reels (reel_id, user_id, caption, video_url, duration_seconds, view_count, upload_date)
VALUES (99, 999, '테스트 릴스', 'https://reels.example.com/fake', 10, 0, '2026-07-14');

-- 실제 실행 결과 (SQLite):
--   sqlite3.IntegrityError: FOREIGN KEY constraint failed
--
-- 왜 막히는가:
--   PRAGMA foreign_keys = ON 상태에서, reels.user_id는 users.user_id를
--   참조하는 FK로 선언되어 있다. FK는 "자식 테이블의 값은 반드시
--   부모 테이블에 실제로 존재하는 값이어야 한다"는 규칙을 강제한다.
--   user_id = 999는 users 테이블에 존재하지 않으므로 참조 무결성이
--   깨지는 것을 DB 엔진이 자동으로 차단한다.
--
-- 어떻게 고쳐야 하는가:
--   (1) users 테이블에 user_id = 999인 사용자를 먼저 INSERT한 뒤 실행하거나,
--   (2) 이미 존재하는 user_id(예: 1~12) 중 하나로 값을 바꿔서 실행한다.
-- 아래는 (2)번 방식으로 수정한 정상 버전이다.
INSERT INTO reels (reel_id, user_id, caption, video_url, duration_seconds, view_count, upload_date)
VALUES (99, 4, '테스트 릴스', 'https://reels.example.com/fake', 10, 0, '2026-07-14');


-- ============================================================
-- [보너스 3] 미니 리포트 - 핵심 지표 3개
-- ============================================================

-- 지표 1: 월별 릴스 업로드 건수 추이
-- 확인 목적: 시간에 따라 콘텐츠 업로드량이 어떻게 변하는지 파악한다
-- (SQLite 전용 함수: strftime)
SELECT strftime('%Y-%m', upload_date) AS upload_month,
       COUNT(*) AS reel_count
FROM reels
GROUP BY upload_month
ORDER BY upload_month;

-- 지표 2: 가장 인기 있는 릴스 TOP 5 (좋아요 수 기준)
-- 확인 목적: 참여도가 가장 높은 콘텐츠를 식별한다
SELECT r.reel_id, r.caption, COUNT(l.like_id) AS like_count
FROM reels r
LEFT JOIN likes l ON r.reel_id = l.reel_id
GROUP BY r.reel_id, r.caption
ORDER BY like_count DESC
LIMIT 5;

-- 지표 3: 참여율이 저조한 사용자 목록 (릴스는 올렸지만 좋아요/댓글이 적은 경우)
-- 확인 목적: 콘텐츠 대비 반응이 낮은 사용자를 파악해 운영 개선 포인트를 찾는다
SELECT u.username,
       COUNT(DISTINCT r.reel_id) AS reel_count,
       COUNT(DISTINCT l.like_id) AS total_likes,
       COUNT(DISTINCT c.comment_id) AS total_comments
FROM users u
INNER JOIN reels r ON u.user_id = r.user_id
LEFT JOIN likes l ON r.reel_id = l.reel_id
LEFT JOIN comments c ON r.reel_id = c.reel_id
GROUP BY u.username
HAVING total_likes + total_comments < 5
ORDER BY total_likes + total_comments ASC;
