FROM registry.access.redhat.com/ubi8/ubi:8.0

COPY cidr-filtering-cni /cidr-filtering-cni
COPY deploy/entrypoint.sh /entrypoint.sh

RUN chmod +x /cidr-filtering-cni && \
chmod +x /entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
