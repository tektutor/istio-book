# The inventory service as a container image.
FROM docker.io/library/python:3.13-slim

# Do not write .pyc files, and print log lines at once.
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["python", "app.py"]
