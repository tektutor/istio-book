# The price feed as a container image. It needs only the standard library.
FROM docker.io/library/python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

WORKDIR /app
COPY app.py .
USER 65532:65532
EXPOSE 7070
ENTRYPOINT ["python", "app.py"]
CMD ["serve", "7070"]
