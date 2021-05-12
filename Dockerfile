FROM ubuntu:latest as installer
RUN apt-get update && apt-get install curl --yes
RUN curl -Lo /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
RUN chmod +0755 /usr/local/bin/jq

FROM public.ecr.aws/bitnami/wordpress:latest as app
COPY --from=installer /usr/local/bin/jq /usr/bin/jq
COPY startup.sh /opt/copilot/scripts/startup.sh
ENTRYPOINT ["/bin/sh", "-c"]
CMD ["/opt/copilot/scripts/startup.sh"]
EXPOSE 8080