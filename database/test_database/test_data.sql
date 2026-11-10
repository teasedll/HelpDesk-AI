-- HelpDesk AI / PostgreSQL / public. Выполняйте в тестовой базе после schema.sql.
-- Если seed.sql уже выполнен, используем существующие строки справочников.
-- После загрузки старого варианта с ролями user и agent используйте
-- отдельную тестовую базу, чтобы избежать конфликта адресов.
-- DBeaver: привяжите вкладку к тестовому подключению, затем выберите
-- «Редактор SQL → Выполнить SQL скрипт». После загрузки откройте queries.sql.
-- Один блок DO выполняется атомарно. Повторный запуск использует те же
-- имена справочников, адреса и метки обращений. Ключи выдаёт PostgreSQL.
-- Пароль всех учебных аккаунтов: HelpDesk-Lab-2026!
-- В users хранятся только индивидуально посоленные хеши Werkzeug PBKDF2.
-- Вложения представлены метаданными. Файлы по указанным путям не создаются.

DO $helpdesk_lab$
DECLARE
    actor record;
    scenario record;
    i integer;
    batch integer;
    phase integer;
    lab_users bigint[] := '{}';
    requester_id bigint;
    agent_id bigint;
    author_id bigint;
    current_ticket_id bigint;
    current_category_id integer;
    prediction_category_id integer;
    current_priority_id integer;
    current_status_id integer;
    ticket_title text;
    ticket_description text;
    ticket_opened timestamp;
    ticket_updated timestamp;
    ticket_closed timestamp;
    location_names text[] := ARRAY['корпус А','корпус Б','библиотека','общежитие','учебный центр'];
    status_names text[] := ARRAY['NEW','WAITING','IN_PROGRESS','RESOLVED','CLOSED'];
    priority_names text[] := ARRAY['LOW','MEDIUM','HIGH','CRITICAL'];
    category_names text[] := ARRAY['Network','Account','Hardware','Software','Other'];
BEGIN
    -- Два одновременных запуска этого набора выполняются последовательно.
    PERFORM pg_advisory_xact_lock(140313327, 20261110);

    INSERT INTO public.roles (name, description)
    SELECT seed.name, seed.description
    FROM (VALUES ('USER','Обычный пользователь'), ('SUPPORT','Сотрудник поддержки'),
                 ('ADMIN','Администратор')) AS seed(name, description)
    WHERE NOT EXISTS (SELECT 1 FROM public.roles r WHERE r.name = seed.name)
    ON CONFLICT (name) DO NOTHING;

    INSERT INTO public.statuses (name, description)
    SELECT seed.name, seed.description
    FROM unnest(status_names, ARRAY['Новая','Ожидание','В работе','Решена','Закрыта'])
         AS seed(name, description)
    WHERE NOT EXISTS (SELECT 1 FROM public.statuses s WHERE s.name = seed.name)
    ON CONFLICT (name) DO NOTHING;

    INSERT INTO public.priorities (name, level, description)
    SELECT seed.name, seed.level::integer, seed.description
    FROM unnest(priority_names, ARRAY['Низкий','Средний','Высокий','Критический'])
         WITH ORDINALITY AS seed(name, description, level)
    WHERE NOT EXISTS (SELECT 1 FROM public.priorities p WHERE p.name = seed.name)
    ON CONFLICT (name) DO NOTHING;

    INSERT INTO public.categories (name, description)
    SELECT seed.name, seed.description
    FROM unnest(category_names, ARRAY['Сеть и интернет','Учётные записи','Оборудование',
              'Программное обеспечение','Прочее'])
         AS seed(name, description)
    WHERE NOT EXISTS (SELECT 1 FROM public.categories c WHERE c.name = seed.name)
    ON CONFLICT (name) DO NOTHING;

    FOR actor IN
        SELECT * FROM (VALUES
            (1, 'Анна Лебедева', 'USER', 'pbkdf2:sha256:1000000$31064604669d0094$63c3912e2453cd03feccc02cc1941ead4abfe05bfca36cd0dda51a738e3d002e'),
            (2, 'Илья Орлов', 'USER', 'pbkdf2:sha256:1000000$7280d594aaa27c70$be09b0031cbcfe94562d70b83d1c08aa07135e8d2bcb58c4455286e87bc80a9c'),
            (3, 'Мария Белова', 'USER', 'pbkdf2:sha256:1000000$afb97c7dface97f5$aee37b4443f38a628a6678f89d3104a85d0cf25670541e28e1b77b600b2685fd'),
            (4, 'Денис Крылов', 'USER', 'pbkdf2:sha256:1000000$cea23768d8e577c8$2c0b77abb7936ab180522519a588af1bd085a0cdaa61869e4bff394b63a19f6d'),
            (5, 'Софья Власова', 'USER', 'pbkdf2:sha256:1000000$267d131df5242869$d462650822d2d03d23fb6b2b4fce2b30828f8522a47f01e2d1ca8c7b846b4ee3'),
            (6, 'Павел Ершов', 'USER', 'pbkdf2:sha256:1000000$f2a715e9c5a57e4f$b643649fc498eebc552a36e1e68d9c88e76e1cb20b77131ecf42a9da08982254'),
            (7, 'Алина Волкова', 'USER', 'pbkdf2:sha256:1000000$6cfbd9b9e6fbadf6$e563bca1710238684ebe781f10570ce8dd4c0581f5fe0d13dcbafa0a8bf4f449'),
            (8, 'Кирилл Лапин', 'USER', 'pbkdf2:sha256:1000000$e47dc4a4dd2f540a$ee40f6ceb01ae6c5bfa0d429737d5f8fed18029f644ecee4ead5c2a1982c533a'),
            (9, 'Елена Морозова', 'USER', 'pbkdf2:sha256:1000000$1fbbbb3f22d9b5d0$f05dc6def771128ed2b6a254f49d3bae0bfb7b57d2c87cfb57af2bf6bc186263'),
            (10, 'Никита Соколов', 'USER', 'pbkdf2:sha256:1000000$5fd77c37dd7c1f57$dc6561854cb06896481d477f53b9fdc211992ad6b4d59ab76cc54c7d0270ee0d'),
            (11, 'Вера Котова', 'USER', 'pbkdf2:sha256:1000000$70a8f9d832361997$89a9a3094889bc02e959c4d8d1b080c8f87255316f2b37e12a0951f206a3c0ce'),
            (12, 'Олег Миронов', 'SUPPORT', 'pbkdf2:sha256:1000000$7fa9c6f056238774$f7950c671c53f4149d11cdb407957bb5d40f77d60476d9bd2464643e109c7aa6'),
            (13, 'Дарья Макарова', 'SUPPORT', 'pbkdf2:sha256:1000000$e28b4f4fc9c226e8$f661ae47a2733dfde09bb6f5081406486804851981f5d59ac598060eaa43a088'),
            (14, 'Артём Громов', 'SUPPORT', 'pbkdf2:sha256:1000000$febc2e5249714424$8732b1dc54ff037ca5641e5fed300200ded2177e3973cd97ab1acdcf60bfd298'),
            (15, 'Юлия Савина', 'SUPPORT', 'pbkdf2:sha256:1000000$646392ef53052129$4f03a1d72a6b15735c2eba9cfed77e1534b25389e812648ca1a38ddb1c7f4717')
        ) AS seed(n, name, role_name, password_hash)
        ORDER BY n
    LOOP
        INSERT INTO public.users (name, email, password_hash, role_id, created_at)
        SELECT actor.name, format('hdai-lab-v1-%s@example.test', actor.n),
               actor.password_hash, r.role_id, timestamp '2026-10-01 09:00'
        FROM public.roles r
        WHERE r.name = actor.role_name
          AND NOT EXISTS (
              SELECT 1 FROM public.users u
              WHERE u.email = format('hdai-lab-v1-%s@example.test', actor.n)
          )
        ON CONFLICT (email) DO NOTHING;

        -- При занятом тестовом адресе с другими данными отменяем загрузку.
        SELECT u.user_id INTO author_id
        FROM public.users u
        JOIN public.roles r ON r.role_id = u.role_id
        WHERE u.email = format('hdai-lab-v1-%s@example.test', actor.n)
          AND u.name = actor.name
          AND u.password_hash = actor.password_hash
          AND r.name = actor.role_name;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Учебный адрес hdai-lab-v1-%@example.test уже занят или изменён', actor.n;
        END IF;
        lab_users[actor.n] := author_id;
    END LOOP;


    -- Десять разных типов инцидентов в пяти подразделениях.
    FOR scenario IN
        SELECT * FROM (VALUES
            (1, 1, 3, 'Wi-Fi отключается на занятии', 'Подключение пропадает через несколько минут. Повторный вход помогает ненадолго.', 'wlan-log.txt', 'text/plain'),
            (2, 2, 2, 'Личный кабинет не принимает пароль', 'После смены пароля портал возвращает на страницу входа.', 'login-error.png', 'image/png'),
            (3, 3, 3, 'Проектор не видит ноутбук', 'На панели отображается «Нет сигнала». Проверены два кабеля HDMI.', 'projector.jpg', 'image/jpeg'),
            (4, 4, 2, 'Не запускается учебная среда Python', 'После обновления ярлык открывает окно ошибки импорта.', 'python-error.txt', 'text/plain'),
            (5, 5, 2, 'Письма на факультет не доставляются', 'Письмо возвращается с кодом 550 при отправке на адрес группы.', 'delivery.txt', 'text/plain'),
            (6, 1, 4, 'Пропало сетевое подключение в аудитории', 'Компьютеры не получают адрес по DHCP. Занятие остановлено.', 'dhcp-log.txt', 'text/plain'),
            (7, 2, 3, 'После замены телефона не работает 2FA', 'Коды со старого устройства недоступны. Требуется восстановить доступ.', 'mfa-screen.png', 'image/png'),
            (8, 3, 1, 'Принтер оставляет полосы', 'Полосы появляются на нескольких пробных страницах после замены картриджа.', 'print-sample.jpg', 'image/jpeg'),
            (9, 4, 3, 'Портал не принимает работы студентов', 'При загрузке PDF на страницу задания возвращается ошибка сервера.', 'portal-error.png', NULL),
            (10, 5, 1, 'Не синхронизируется почтовый календарь', 'Приглашения видны в браузере, но отсутствуют в настольном клиенте.', 'sync-log.txt', 'text/plain')
        ) AS seed(n, category_no, priority_no, subject, detail, file_name, mime)
        ORDER BY n
    LOOP
        FOR batch IN 1..5 LOOP
            i := (batch - 1) * 10 + scenario.n;
            phase := (scenario.n + batch) % 5 + 1;
            requester_id := lab_users[(i - 1) % 11 + 1];
            agent_id := lab_users[12 + (scenario.n + 2 * batch) % 4];
            ticket_opened := timestamp '2026-10-05 08:00'
                             + (batch - 1) * interval '7 days'
                             + (scenario.n - 1) * interval '3 hours';
            ticket_updated := ticket_opened + (phase - 1) * interval '3 hours';
            ticket_closed := CASE WHEN phase >= 4 THEN ticket_updated END;
            ticket_title := format('[HDAI-LAB-V1-%s] %s', lpad(i::text, 2, '0'), scenario.subject);
            ticket_description := format('Подразделение: %s. %s', location_names[batch], scenario.detail);

            IF EXISTS (
                SELECT 1 FROM public.tickets t
                WHERE t.user_id = requester_id
                  AND t.created_at = ticket_opened
                  AND left(t.title, 16) = left(ticket_title, 16)
            ) THEN
                CONTINUE;
            END IF;

            SELECT category_id INTO STRICT current_category_id
            FROM public.categories WHERE name = category_names[scenario.category_no];
            SELECT priority_id INTO STRICT current_priority_id
            FROM public.priorities WHERE name = priority_names[scenario.priority_no];
            SELECT status_id INTO STRICT current_status_id
            FROM public.statuses WHERE name = status_names[phase];

            INSERT INTO public.tickets (user_id, category_id, priority_id, status_id,
                                        assigned_to, title, description, created_at, updated_at, closed_at)
            VALUES (requester_id, CASE WHEN phase = 1 THEN NULL ELSE current_category_id END,
                    current_priority_id, current_status_id, CASE WHEN phase <= 2 THEN NULL ELSE agent_id END,
                    ticket_title, ticket_description, ticket_opened, ticket_updated, ticket_closed)
            RETURNING ticket_id INTO current_ticket_id;

            INSERT INTO public.ticket_history (ticket_id, old_status_id, new_status_id, changed_by, changed_at)
            SELECT current_ticket_id, previous.status_id, next.status_id,
                   CASE WHEN step = 1 THEN requester_id ELSE agent_id END,
                   ticket_opened + (step - 1) * interval '3 hours'
            FROM generate_series(1, phase) AS steps(step)
            JOIN public.statuses next ON next.name = status_names[step]
            LEFT JOIN public.statuses previous ON previous.name = status_names[step - 1];

            IF phase >= 3 THEN
                INSERT INTO public.comments (ticket_id, user_id, text, created_at)
                VALUES (current_ticket_id, agent_id,
                        'Взяли в работу. Проверяем журнал и повторяем сценарий.',
                        ticket_opened + interval '6 hours');
            END IF;

            IF phase >= 4 AND batch <= 3 THEN
                INSERT INTO public.comments (ticket_id, user_id, text, created_at)
                VALUES (current_ticket_id, agent_id,
                        'Проверка пройдена. Просим подтвердить, что проблема больше не повторяется.',
                        ticket_opened + interval '9 hours');
            END IF;

            IF batch <= 2 THEN
                SELECT category_id INTO STRICT prediction_category_id
                FROM public.categories
                WHERE name = category_names[
                    CASE WHEN scenario.n % 3 = 0 THEN scenario.category_no % 5 + 1
                         ELSE scenario.category_no END
                ];
                INSERT INTO public.ml_predictions
                    (ticket_id, predicted_category_id, confidence, model_version, created_at)
                VALUES (current_ticket_id, prediction_category_id,
                        0.47 + scenario.n * 0.047, 'lab-v1', ticket_opened + interval '1 minute');
                IF scenario.n % 2 = 0 THEN
                    INSERT INTO public.ml_predictions
                        (ticket_id, predicted_category_id, confidence, model_version, created_at)
                    VALUES (current_ticket_id, current_category_id,
                            0.78 + scenario.n * 0.019, 'lab-v2', ticket_opened + interval '3 minutes');
                END IF;
            END IF;

            IF batch = 1 THEN
                INSERT INTO public.attachments
                    (ticket_id, user_id, file_name, file_path, file_type, file_size, uploaded_at)
                VALUES (current_ticket_id, requester_id, scenario.file_name,
                        format('fixtures/helpdesk-lab-v1/%s/%s', i, scenario.file_name),
                        scenario.mime, CASE WHEN scenario.mime IS NOT NULL THEN 2048 + i * 997 END,
                        ticket_opened);
            END IF;
        END LOOP;
    END LOOP;
END;
$helpdesk_lab$;
