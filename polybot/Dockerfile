FROM python:3.10-slim
RUN pip install --upgrade pip
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python3", "app.py"]

