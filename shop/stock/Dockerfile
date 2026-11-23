# The stock service as a container image. The build generates the
# Python code for the gRPC API from stock.proto.
FROM docker.io/library/python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY stock.proto app.py client.py watch.py ./
RUN python -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. \
      stock.proto
USER 65532:65532
EXPOSE 9090
ENTRYPOINT ["python", "app.py"]
