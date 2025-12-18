import sys
import os
from flask import Flask
from flask_cors import CORS

# Adiciona o diretório raiz do projeto ao sys.path
# Isso permite que módulos na raiz (como extensions, email_service, models) sejam importados
current_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(current_dir, '..', '..'))
sys.path.insert(0, project_root)

from .routes import gerenciamento_financeiro_bp

app = Flask(__name__)
CORS(app, origins=["*"], supports_credentials=True)

# Registrar o blueprint
app.register_blueprint(gerenciamento_financeiro_bp)

# Configurações se precisar
app.config['SECRET_KEY'] = 'sua-chave-secreta'