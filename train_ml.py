"""Train a baseline model from a labeled CSV with columns text,category."""
import csv
from pathlib import Path
import joblib
from sklearn.pipeline import make_pipeline
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression

path=Path('data/tickets.csv')
if not path.exists():
    raise SystemExit('Создайте data/tickets.csv с колонками text,category (не менее двух классов).')
with path.open(encoding='utf-8-sig',newline='') as f:
    rows=list(csv.DictReader(f))
texts=[r['text'] for r in rows]
labels=[r['category'] for r in rows]
allowed={'Network','Hardware','Software','Account','Other'}
if len(rows)<10 or len(set(labels))<2 or not set(labels)<=allowed:
    raise SystemExit('Нужно хотя бы 10 размеченных примеров, 2 класса и корректные категории.')
model=make_pipeline(TfidfVectorizer(ngram_range=(1,2),min_df=1),LogisticRegression(max_iter=1000))
model.fit(texts,labels)
Path('models').mkdir(exist_ok=True)
joblib.dump(model,'models/ticket_classifier.joblib')
print('Модель сохранена. Это базовый прототип; оцените качество на отдельной тестовой выборке.')
