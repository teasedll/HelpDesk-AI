"""Optional classifier. Without a trained model tickets go to Other (no fabricated confidence)."""
import os
from pathlib import Path

def predict_category(text):
    path=Path(os.getenv('ML_MODEL_PATH','models/ticket_classifier.joblib'))
    if path.is_file():
        import joblib
        model=joblib.load(path)  # Load only a trusted local model file.
        label=str(model.predict([text])[0])
        if label not in {'Network','Hardware','Software','Account','Other'}:
            label='Other'
        confidence=None
        if hasattr(model,'predict_proba'):
            confidence=round(float(max(model.predict_proba([text])[0])),4)
        return {'category':label,'confidence':confidence,'version':'tfidf-logreg-v1'}
    return {'category':'Other','confidence':None,'version':'untrained'}
