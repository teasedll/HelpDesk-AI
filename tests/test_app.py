from app import create_app
from app.ml import predict_category

def test_app_routes_exist():
    app=create_app({'TESTING':True,'SECRET_KEY':'test-key'})
    routes={r.rule for r in app.url_map.iter_rules()}
    assert {'/login','/register','/tickets','/tickets/new','/stats'} <= routes

def test_untrained_fallback(monkeypatch):
    monkeypatch.setenv('ML_MODEL_PATH','models/does-not-exist.joblib')
    result=predict_category('Нет интернета')
    assert result['category']=='Other'
    assert result['confidence'] is None
