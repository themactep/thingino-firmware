FROM python:3.13-slim

WORKDIR /app

COPY collector.py /app/collector.py

RUN useradd --system --uid 10001 --home-dir /app train \
	&& mkdir -p /data \
	&& chown train:train /data

USER train

ENV TRAIN_BIND=0.0.0.0:8080 \
	TRAIN_DATA_DIR=/data

EXPOSE 8080
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
	CMD ["python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=3)"]

CMD ["python3", "/app/collector.py"]
