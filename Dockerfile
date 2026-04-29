FROM python:3.12-alpine

ENV SERVE_ROOT=/srv/www
ENV HOST=0.0.0.0
ENV PORT=8080

COPY build/ /srv/www/
COPY serve_web.py /usr/local/bin/serve_web.py
RUN chmod +x /usr/local/bin/serve_web.py

EXPOSE 8080

CMD ["python3", "/usr/local/bin/serve_web.py"]
