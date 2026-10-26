INSERT INTO roles(name,description) VALUES ('USER','Обычный пользователь'),('SUPPORT','Сотрудник поддержки'),('ADMIN','Администратор') ON CONFLICT (name) DO NOTHING;
INSERT INTO categories(name,description) VALUES ('Network','Сеть и интернет'),('Hardware','Оборудование'),('Software','Программное обеспечение'),('Account','Учётные записи'),('Other','Прочее') ON CONFLICT (name) DO NOTHING;
INSERT INTO priorities(name,level,description) VALUES ('LOW',1,'Низкий'),('MEDIUM',2,'Средний'),('HIGH',3,'Высокий'),('CRITICAL',4,'Критический') ON CONFLICT (name) DO NOTHING;
INSERT INTO statuses(name,description) VALUES ('NEW','Новая'),('IN_PROGRESS','В работе'),('WAITING','Ожидание'),('RESOLVED','Решена'),('CLOSED','Закрыта') ON CONFLICT (name) DO NOTHING;
