-- ============================================================
-- E-Commerce Delivery Delay Analysis
-- Dataset: Brazilian E-Commerce Public Dataset by Olist (Kaggle)
-- Tool: SQLite (DB Browser for SQLite)
-- ============================================================


-- ============================================================
-- STEP 1: Create a view calculating delivery delay for every
-- delivered order (positive = late, negative = early/on-time)
-- ============================================================
CREATE VIEW orders_with_delay AS
SELECT order_id,
       customer_id,
       order_estimated_delivery_date,
       order_delivered_customer_date,
       ROUND(julianday(order_delivered_customer_date) - julianday(order_estimated_delivery_date), 1) AS delay_days
FROM orders
WHERE order_status = 'delivered';


-- Quick check: confirm the view works
SELECT COUNT(*) FROM orders_with_delay;
-- Result: 96,478 delivered orders


-- ============================================================
-- STEP 2: Join delay data with review scores (row-level check)
-- ============================================================
SELECT o.order_id, o.delay_days, r.review_score
FROM orders_with_delay o
JOIN order_reviews r ON o.order_id = r.order_id
LIMIT 20;


-- ============================================================
-- STEP 3: KEY INSIGHT #1 — Average review score by delay bucket
-- ============================================================
SELECT 
  CASE 
    WHEN delay_days <= 0 THEN 'On-time or early'
    WHEN delay_days BETWEEN 0.1 AND 3 THEN '1-3 days late'
    WHEN delay_days BETWEEN 3.1 AND 7 THEN '4-7 days late'
    ELSE '8+ days late'
  END AS delay_bucket,
  COUNT(*) AS num_orders,
  ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders_with_delay o
JOIN order_reviews r ON o.order_id = r.order_id
GROUP BY delay_bucket
ORDER BY avg_review_score DESC;

-- RESULT:
-- On-time or early   | 88,715 orders | 4.29 avg review score
-- 1-3 days late       |  2,605 orders | 3.75
-- 4-7 days late       |  1,791 orders | 2.30
-- 8+ days late        |  3,250 orders | 1.74


-- ============================================================
-- STEP 4: Repeat purchase analysis
-- NOTE: customer_id is unique PER ORDER in this dataset.
-- customer_unique_id (from the customers table) identifies
-- the actual person, so we use that for repeat-purchase logic.
-- ============================================================

-- 4a. Build a helper table: order count per real customer
-- (created as a physical table instead of a live subquery
-- because the live subquery version was too slow to join twice)
CREATE TABLE customer_order_counts AS
SELECT c2.customer_unique_id, COUNT(*) AS order_count
FROM orders o2
JOIN customers c2 ON o2.customer_id = c2.customer_id
GROUP BY c2.customer_unique_id;

-- Confirm row count
SELECT COUNT(*) FROM customer_order_counts;
-- Result: 96,096 unique customers


-- 4b. KEY INSIGHT #2 — Repeat purchase rate: delayed vs on-time
SELECT 
  CASE WHEN o.delay_days <= 0 THEN 'On-time or early' ELSE 'Late' END AS delivery_status,
  COUNT(DISTINCT c.customer_unique_id) AS total_customers,
  SUM(CASE WHEN cc.order_count > 1 THEN 1 ELSE 0 END) AS repeat_customers
FROM orders_with_delay o
JOIN customers c ON o.customer_id = c.customer_id
JOIN customer_order_counts cc ON c.customer_unique_id = cc.customer_unique_id
GROUP BY delivery_status;

-- RESULT:
-- Late              | 7,718 total customers | 426 repeat  = 5.52% repeat rate
-- On-time or early  | 85,949 total customers | 5,673 repeat = 6.60% repeat rate


-- ============================================================
-- STEP 5: KEY INSIGHT #3 — Regional breakdown (delay & review
-- score by state)
-- ============================================================
SELECT 
  c.customer_state,
  COUNT(*) AS total_orders,
  ROUND(AVG(o.delay_days), 2) AS avg_delay_days,
  ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM orders_with_delay o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_reviews r ON o.order_id = r.order_id
GROUP BY c.customer_state
HAVING COUNT(*) > 100
ORDER BY avg_delay_days DESC;

-- RESULT (highlights):
-- No state is late on average.
-- AL (Alagoas) has the narrowest delivery buffer (-8.15 days) 
--   and lowest review score (3.84) among high-volume states.
-- RO (Rondonia) and AM (Amazonas) have the widest buffer 
--   (~-19 days early) — likely padded estimates for remote regions.
-- Review scores stay fairly flat (3.84-4.25) across states,
-- confirming delay severity (Step 3) is a stronger driver of
-- satisfaction than geography.


-- ============================================================
-- SUMMARY OF KEY FINDINGS
-- ============================================================
-- 1. Orders delayed 8+ days average 1.74 stars vs 4.29 stars 
--    for on-time orders (a 2.55-star drop).
-- 2. Late-delivery customers have a 5.52% repeat purchase rate 
--    vs 6.60% for on-time customers (~16% relative drop).
-- 3. Delay severity is a stronger predictor of dissatisfaction 
--    than customer region/state.
