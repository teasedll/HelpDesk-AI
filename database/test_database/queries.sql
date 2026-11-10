-- 01. Вывести названия категорий в алфавитном порядке.
SELECT name
FROM public.categories
ORDER BY name;

-- 02. Показать пять последних обращений.
SELECT ticket_id, title, created_at
FROM public.tickets
ORDER BY created_at DESC, ticket_id DESC
LIMIT 5;

-- 03. Найти обращения, в заголовках которых встречается Wi-Fi.
SELECT ticket_id, title
FROM public.tickets
WHERE title ILIKE '%wi-fi%'
ORDER BY ticket_id;

-- 04. Вывести обращения, у которых нет исполнителя или категории.
SELECT ticket_id, title, assigned_to, category_id
FROM public.tickets
WHERE assigned_to IS NULL OR category_id IS NULL
ORDER BY ticket_id;

-- 05. Показать обращения за октябрь 2026 года.
SELECT ticket_id, title, created_at
FROM public.tickets
WHERE created_at >= DATE '2026-10-01'
  AND created_at < DATE '2026-11-01'
ORDER BY created_at, ticket_id;

-- 06. Найти авторов обращений, исключив роли SUPPORT и ADMIN через NOT IN.
SELECT u.user_id, u.name, r.name AS role_name
FROM public.users u
JOIN public.roles r ON r.role_id = u.role_id
WHERE r.name NOT IN ('SUPPORT', 'ADMIN')
  AND EXISTS (SELECT 1 FROM public.tickets t WHERE t.user_id = u.user_id)
ORDER BY u.user_id;

-- 07. Вывести обращения с высоким или критическим приоритетом и их статус.
SELECT t.ticket_id, t.title, p.name AS priority, s.name AS status
FROM public.tickets t
JOIN public.priorities p ON p.priority_id = t.priority_id
JOIN public.statuses s ON s.status_id = t.status_id
WHERE p.name IN ('HIGH', 'CRITICAL')
ORDER BY p.level DESC, t.created_at, t.ticket_id;

-- 08. Показать автора и исполнителя каждого обращения, включая неназначенные.
SELECT t.ticket_id, t.title, requester.name AS requester,
       COALESCE(agent.name, 'Не назначен') AS assignee
FROM public.tickets t
JOIN public.users requester ON requester.user_id = t.user_id
LEFT JOIN public.users agent ON agent.user_id = t.assigned_to
ORDER BY t.ticket_id;

-- 09. Показать метаданные вложений и пометить пропуски.
SELECT a.attachment_id, t.title, a.file_name, a.file_type, a.file_size,
       CASE WHEN a.file_type IS NULL OR a.file_size IS NULL THEN 'неполные'
            ELSE 'полные' END AS metadata
FROM public.attachments a
JOIN public.tickets t ON t.ticket_id = a.ticket_id
ORDER BY a.attachment_id;

-- 10. Подсчитать обращения по каждому статусу, включая статусы без обращений.
SELECT s.name AS status, COUNT(t.ticket_id) AS ticket_count
FROM public.statuses s
LEFT JOIN public.tickets t ON t.status_id = s.status_id
GROUP BY s.status_id, s.name
ORDER BY ticket_count DESC, s.name;

-- 11. Найти авторов, создавших не менее двух обращений.
SELECT u.user_id, u.name, COUNT(*) AS ticket_count
FROM public.users u
JOIN public.tickets t ON t.user_id = u.user_id
GROUP BY u.user_id, u.name
HAVING COUNT(*) >= 2
ORDER BY ticket_count DESC, u.user_id;

-- 12. Подсчитать назначенные и завершённые обращения по неделям создания.
SELECT date_trunc('week', created_at)::date AS week_start,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE assigned_to IS NOT NULL) AS assigned_count,
       COUNT(*) FILTER (WHERE closed_at IS NOT NULL) AS completed_count
FROM public.tickets
GROUP BY 1
ORDER BY 1;

-- 13. Найти обращения без комментариев с помощью NOT EXISTS.
SELECT t.ticket_id, t.title
FROM public.tickets t
WHERE NOT EXISTS (
    SELECT 1 FROM public.comments c WHERE c.ticket_id = t.ticket_id
)
ORDER BY t.ticket_id;

-- 14. Найти прогнозы, уверенность которых выше средней по всем прогнозам.
SELECT m.prediction_id, m.ticket_id, c.name AS predicted_category,
       m.model_version, m.confidence
FROM public.ml_predictions m
JOIN public.categories c ON c.category_id = m.predicted_category_id
WHERE m.confidence > (SELECT AVG(confidence) FROM public.ml_predictions)
ORDER BY m.confidence DESC, m.prediction_id;

-- 15. Показать число комментариев и вложений для каждого обращения.
-- Считаем в двух CTE, чтобы комментарии и вложения не перемножались при JOIN.
WITH comment_counts AS (
    SELECT ticket_id, COUNT(*) AS total FROM public.comments GROUP BY ticket_id
), attachment_counts AS (
    SELECT ticket_id, COUNT(*) AS total FROM public.attachments GROUP BY ticket_id
)
SELECT t.ticket_id, t.title, COALESCE(c.total, 0) AS comments,
       COALESCE(a.total, 0) AS attachments
FROM public.tickets t
LEFT JOIN comment_counts c ON c.ticket_id = t.ticket_id
LEFT JOIN attachment_counts a ON a.ticket_id = t.ticket_id
ORDER BY comments DESC, attachments DESC, t.ticket_id;

-- 16. Найти среднее время до закрытия по категориям в часах.
WITH durations AS (
    SELECT category_id, EXTRACT(EPOCH FROM (closed_at - created_at)) / 3600 AS hours
    FROM public.tickets
    WHERE closed_at IS NOT NULL
)
SELECT COALESCE(c.name, 'Без категории') AS category,
       COUNT(*) AS completed_count, ROUND(AVG(d.hours), 2) AS avg_hours
FROM durations d
LEFT JOIN public.categories c ON c.category_id = d.category_id
GROUP BY c.category_id, c.name
ORDER BY avg_hours DESC, category;

-- 17. Показать первый ответ сотрудника поддержки по каждому обращению,
-- на которое ответил сотрудник. MIN выбирает самое раннее время ответа.
SELECT t.ticket_id, t.title, MIN(c.created_at) AS first_reply_at
FROM public.tickets t
JOIN public.comments c ON c.ticket_id = t.ticket_id
JOIN public.users u ON u.user_id = c.user_id
JOIN public.roles r ON r.role_id = u.role_id
WHERE r.name IN ('SUPPORT', 'ADMIN')
  AND c.user_id <> t.user_id
GROUP BY t.ticket_id, t.title
ORDER BY t.ticket_id;

-- 18. Найти ML-прогнозы, которые не совпали с назначенной категорией.
SELECT m.prediction_id, t.title, m.model_version,
       actual.name AS actual_category, predicted.name AS predicted_category
FROM public.ml_predictions m
JOIN public.tickets t ON t.ticket_id = m.ticket_id
JOIN public.categories actual ON actual.category_id = t.category_id
JOIN public.categories predicted ON predicted.category_id = m.predicted_category_id
WHERE m.predicted_category_id <> t.category_id
ORDER BY m.prediction_id;

-- 19. Показать переходы между статусами. Первичная установка статуса
-- исключается, поскольку у неё нет предыдущего статуса.
SELECT h.ticket_id, previous.name AS previous_status,
       current_status.name AS new_status, h.changed_at
FROM public.ticket_history h
JOIN public.statuses previous ON previous.status_id = h.old_status_id
JOIN public.statuses current_status ON current_status.status_id = h.new_status_id
ORDER BY h.ticket_id, h.changed_at, h.history_id;

-- 20. Для каждой версии модели посчитать число прогнозов и число совпадений.
-- Учитываем только обращения, которым назначили категорию.
SELECT m.model_version, COUNT(*) AS evaluated,
       COUNT(*) FILTER (
           WHERE m.predicted_category_id = t.category_id
       ) AS matches
FROM public.ml_predictions m
JOIN public.tickets t ON t.ticket_id = m.ticket_id
WHERE t.category_id IS NOT NULL
GROUP BY m.model_version
ORDER BY m.model_version;
