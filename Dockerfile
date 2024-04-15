FROM debian:bullseye

WORKDIR /opt/fgtconfig

RUN apt-get update && \
    apt-get install -y perl \
                       libmoose-perl \
                       libnet-netmask-perl \
                       libxml-libxml-perl \
                       cpanminus \
                       libmojolicious-perl && \
    rm -rf /var/lib/apt/lists/*

ENV PERL5LIB="${PERL5LIB}:/opt/fgtconfig"

COPY . .

EXPOSE 8080

ENTRYPOINT [ "perl", "./fgtconfig.pl", "-serve" ]