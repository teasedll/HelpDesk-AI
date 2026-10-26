import os
import secrets
from functools import wraps
from flask import Flask, abort, flash, g, redirect, render_template, request, session, url_for
from psycopg import connect
from psycopg.rows import dict_row
from psycopg.errors import UniqueViolation
from werkzeug.security import generate_password_hash, check_password_hash
from dotenv import load_dotenv
from .ml import predict_category

load_dotenv()

def create_app(test_config=None):
    app = Flask(__name__)
    app.config.update(SECRET_KEY=os.getenv('SECRET_KEY') or secrets.token_hex(32), DATABASE_URL=os.getenv('DATABASE_URL', 'postgresql://localhost:5432/helpdesk_ai'))
    if test_config:
        app.config.update(test_config)

    def db():
        return connect(app.config['DATABASE_URL'], row_factory=dict_row)

    def query(sql, params=(), one=False):
        with db() as conn:
            with conn.cursor() as cur:
                cur.execute(sql, params)
                return cur.fetchone() if one else cur.fetchall()

    def login_required(fn):
        @wraps(fn)
        def wrapped(*args, **kwargs):
            if not g.user:
                return redirect(url_for('login'))
            return fn(*args, **kwargs)
        return wrapped

    def staff_required(fn):
        @wraps(fn)
        @login_required
        def wrapped(*args, **kwargs):
            if g.user['role'] not in ('SUPPORT', 'ADMIN'):
                abort(403)
            return fn(*args, **kwargs)
        return wrapped

    @app.before_request
    def before():
        if 'csrf' not in session:
            session['csrf'] = secrets.token_urlsafe(32)
        g.user = None
        if session.get('user_id'):
            g.user = query('SELECT u.user_id, u.name, u.email, r.name AS role FROM users u JOIN roles r ON r.role_id=u.role_id WHERE u.user_id=%s', (session['user_id'],), True)
        if request.method == 'POST' and request.form.get('csrf_token') != session['csrf']:
            abort(400, 'Неверный CSRF-токен')

    @app.context_processor
    def context():
        return {'csrf_token': lambda: session.get('csrf', '')}

    @app.get('/')
    def index():
        return redirect(url_for('tickets') if g.user else url_for('login'))

    @app.route('/register', methods=['GET', 'POST'])
    def register():
        if request.method == 'POST':
            name = request.form.get('name', '').strip()
            email = request.form.get('email', '').strip().lower()
            password = request.form.get('password', '')
            if not name or len(name)>100 or '@' not in email or len(email)>255 or len(password)<8:
                flash('Введите имя, корректный email и пароль от 8 символов.', 'error')
            else:
                try:
                    with db() as conn:
                        with conn.cursor() as cur:
                            cur.execute("INSERT INTO users(name,email,password_hash,role_id) VALUES (%s,%s,%s,(SELECT role_id FROM roles WHERE name='USER')) RETURNING user_id", (name,email,generate_password_hash(password)))
                            user_id=cur.fetchone()['user_id']
                    session.clear()
                    session['user_id']=user_id
                    flash('Регистрация завершена.', 'success')
                    return redirect(url_for('tickets'))
                except UniqueViolation:
                    flash('Такой email уже зарегистрирован.', 'error')
        return render_template('register.html')

    @app.route('/login', methods=['GET', 'POST'])
    def login():
        if request.method == 'POST':
            user=query('SELECT user_id,password_hash FROM users WHERE email=%s', (request.form.get('email','').strip().lower(),), True)
            if user and check_password_hash(user['password_hash'], request.form.get('password','')):
                session.clear()
                session['user_id']=user['user_id']
                return redirect(url_for('tickets'))
            flash('Неверный email или пароль.', 'error')
        return render_template('login.html')

    @app.post('/logout')
    @login_required
    def logout():
        session.clear()
        return redirect(url_for('login'))

    @app.get('/tickets')
    @login_required
    def tickets():
        sql="""SELECT t.ticket_id,t.title,t.created_at,c.name AS category,s.name AS status,p.name AS priority,u.name AS author FROM tickets t LEFT JOIN categories c ON c.category_id=t.category_id JOIN statuses s ON s.status_id=t.status_id JOIN priorities p ON p.priority_id=t.priority_id JOIN users u ON u.user_id=t.user_id"""
        params=()
        if g.user['role']=='USER':
            sql+=' WHERE t.user_id=%s'
            params=(g.user['user_id'],)
        sql+=' ORDER BY t.created_at DESC, t.ticket_id DESC LIMIT 200'
        return render_template('tickets.html', tickets=query(sql,params))

    @app.route('/tickets/new', methods=['GET','POST'])
    @login_required
    def new_ticket():
        priorities=query('SELECT priority_id,name FROM priorities ORDER BY level')
        if request.method=='POST':
            title=request.form.get('title','').strip()
            description=request.form.get('description','').strip()
            try:
                priority_id=int(request.form.get('priority_id',''))
            except ValueError:
                priority_id=-1
            if not title or len(title)>200 or not description or len(description)>10000 or priority_id not in {p['priority_id'] for p in priorities}:
                flash('Проверьте название, описание и приоритет.', 'error')
            else:
                result=predict_category(title+' '+description)
                with db() as conn:
                    with conn.cursor() as cur:
                        cur.execute("INSERT INTO tickets(user_id,category_id,priority_id,status_id,title,description) VALUES (%s,(SELECT category_id FROM categories WHERE name=%s),%s,(SELECT status_id FROM statuses WHERE name='NEW'),%s,%s) RETURNING ticket_id", (g.user['user_id'],result['category'],priority_id,title,description))
                        tid=cur.fetchone()['ticket_id']
                        if result['confidence'] is not None:
                            cur.execute('INSERT INTO ml_predictions(ticket_id,predicted_category_id,confidence,model_version) VALUES (%s,(SELECT category_id FROM categories WHERE name=%s),%s,%s)',(tid,result['category'],result['confidence'],result['version']))
                flash('Заявка создана.', 'success')
                return redirect(url_for('ticket_detail',ticket_id=tid))
        return render_template('new_ticket.html',priorities=priorities)

    def visible_ticket(ticket_id):
        ticket=query("""SELECT t.*,c.name AS category,s.name AS status,p.name AS priority,u.name AS author FROM tickets t LEFT JOIN categories c ON c.category_id=t.category_id JOIN statuses s ON s.status_id=t.status_id JOIN priorities p ON p.priority_id=t.priority_id JOIN users u ON u.user_id=t.user_id WHERE t.ticket_id=%s""",(ticket_id,),True)
        if not ticket or (g.user['role']=='USER' and ticket['user_id']!=g.user['user_id']):
            abort(404)
        return ticket

    @app.get('/tickets/<int:ticket_id>')
    @login_required
    def ticket_detail(ticket_id):
        ticket=visible_ticket(ticket_id)
        comments=query('SELECT c.text,c.created_at,u.name FROM comments c JOIN users u ON u.user_id=c.user_id WHERE c.ticket_id=%s ORDER BY c.created_at',(ticket_id,))
        history=query('SELECT h.changed_at,old.name AS old_status,new.name AS new_status,u.name AS author FROM ticket_history h LEFT JOIN statuses old ON old.status_id=h.old_status_id JOIN statuses new ON new.status_id=h.new_status_id JOIN users u ON u.user_id=h.changed_by WHERE h.ticket_id=%s ORDER BY h.changed_at DESC',(ticket_id,))
        statuses=query('SELECT status_id,name FROM statuses ORDER BY status_id') if g.user['role']!='USER' else []
        return render_template('ticket_detail.html',ticket=ticket,comments=comments,history=history,statuses=statuses)

    @app.post('/tickets/<int:ticket_id>/comment')
    @login_required
    def add_comment(ticket_id):
        visible_ticket(ticket_id)
        body=request.form.get('text','').strip()
        if not body or len(body)>5000:
            flash('Комментарий должен содержать от 1 до 5000 символов.', 'error')
        else:
            query('INSERT INTO comments(ticket_id,user_id,text) VALUES (%s,%s,%s) RETURNING comment_id',(ticket_id,g.user['user_id'],body),True)
            flash('Комментарий добавлен.', 'success')
        return redirect(url_for('ticket_detail',ticket_id=ticket_id))

    @app.post('/tickets/<int:ticket_id>/status')
    @staff_required
    def change_status(ticket_id):
        ticket=visible_ticket(ticket_id)
        try:
            new_id=int(request.form.get('status_id',''))
        except ValueError:
            abort(400)
        status=query('SELECT name FROM statuses WHERE status_id=%s',(new_id,),True)
        if not status:
            abort(400)
        if new_id!=ticket['status_id']:
            with db() as conn:
                with conn.cursor() as cur:
                    cur.execute('UPDATE tickets SET status_id=%s,updated_at=CURRENT_TIMESTAMP,closed_at=CASE WHEN %s THEN CURRENT_TIMESTAMP ELSE NULL END WHERE ticket_id=%s',(new_id,status['name']=='CLOSED',ticket_id))
                    cur.execute('INSERT INTO ticket_history(ticket_id,old_status_id,new_status_id,changed_by) VALUES (%s,%s,%s,%s)',(ticket_id,ticket['status_id'],new_id,g.user['user_id']))
        return redirect(url_for('ticket_detail',ticket_id=ticket_id))

    @app.get('/stats')
    @staff_required
    def stats():
        rows=query('SELECT s.name,COUNT(t.ticket_id) AS count FROM statuses s LEFT JOIN tickets t ON t.status_id=s.status_id GROUP BY s.status_id,s.name ORDER BY s.status_id')
        return render_template('stats.html',rows=rows)

    return app
