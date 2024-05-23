FROM mysql:8.0.37-debian

RUN ln -sf /bin/bash /bin/sh

RUN apt-get update \
    && apt-get install -y --no-install-recommends lsb-release wget apt-transport-https ca-certificates gnupg \
    && wget -O - 'https://repo.proxysql.com/ProxySQL/proxysql-2.6.x/repo_pub_key' | apt-key add - \
    && echo "deb https://repo.proxysql.com/ProxySQL/proxysql-2.6.x/$(lsb_release -sc)/ ./" | tee /etc/apt/sources.list.d/proxysql.list \
    && apt-get update \
    && apt-get install -y proxysql

RUN echo "[mysqld]" >> /etc/mysql/my.cnf
RUN echo "default-authentication-plugin=mysql_native_password" >> /etc/mysql/my.cnf

# Start ProxySQL as a Service
CMD ["proxysql", "-f", "-c", "/etc/proxysql.cnf"]