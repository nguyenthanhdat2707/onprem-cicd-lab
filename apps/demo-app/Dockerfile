ARG PYTHON_BASE_IMAGE
FROM ${PYTHON_BASE_IMAGE}

# Alpine 3.24 base contains krb5-libs 1.22.2-r1; install the patched release.
RUN apk add --no-cache "krb5-libs=1.22.3-r0"

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8080
WORKDIR /app
COPY app.py /app/app.py
USER 10001:10001
EXPOSE 8080
CMD ["python", "/app/app.py"]
