# DOCKER-VERSION 1.12.3
FROM debian:jessie
MAINTAINER  Richard Challis/Lepbase contact@lepbase.org

ENV TERM xterm
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -y lsb-release apt-utils

RUN sed -i "s/$(lsb_release -sc) main/$(lsb_release -sc) main contrib non-free/" /etc/apt/sources.list

# accepts Microsoft EULA agreement without prompting
# view EULA at http://wwww.microsoft.com/typography/fontpack/eula.htm
RUN { echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true; } | debconf-set-selections \
    && apt-get update && apt-get install -y ttf-mscorefonts-installer

# install packages
RUN apt-get update && apt-get install -y \
        mysql-common \
        mysql-client \
        libmysqlclient*-dev \
        libgdbm-dev \
        libperl-dev \
        libxml2-dev \
        memcachedb \
        libmemcached-dev \
        libevent-dev \
        acedb-other-dotter \
        make \
        curl \
        gcc \
        php5-gd \
        freetype* \
        libgd2-xpm-dev \
        openssl \
        libssl-dev \
        graphviz \
        libcurl4-openssl-dev \
        default-jre \
        cpanminus \
        vcftools \
        tabix \
        libhts1 \
        libhts-dev

RUN cpanm --force WWW::Curl::Multi

WORKDIR /tmp
RUN wget -q http://apache.mirror.anlx.net/httpd/CHANGES_2.2 \
    && export APACHEVERSION=`grep "Changes with" CHANGES_2.2 | head -n 1 | cut -d" " -f 4` \
    && wget -q http://apache.mirror.anlx.net/httpd/httpd-$APACHEVERSION.tar.gz \
    && tar xzf httpd-$APACHEVERSION.tar.gz \
    && cd httpd-$APACHEVERSION \
    && ./configure --with-included-apr --enable-deflate --enable-headers --enable-expires --enable-rewrite --enable-proxy \
    && make && make install

# install the latest version of mod_perl
WORKDIR /tmp
RUN wget -q -O tmp.html http://www.cpan.org/modules/by-module/Apache2/ \
    && MODPERLTAR=`grep -oP "mod_perl.*?tar" tmp.html | sort -Vr | head -n 1` \
    && MODPERLVERSION=${MODPERLTAR%.*} \
    && wget http://www.cpan.org/modules/by-module/Apache2/$MODPERLVERSION.tar.gz \
    && tar xzf $MODPERLVERSION.tar.gz \
    && cd $MODPERLVERSION \
    && perl Makefile.PL MP_APXS=/usr/local/apache2/bin/apxs \
    && make && make install

RUN apt-get install -y git

# install Tabix.pm
WORKDIR /tmp
RUN git clone https://github.com/samtools/tabix
WORKDIR /tmp/tabix/perl
RUN perl Makefile.PL \
    && make && make install

# install Htslib.pm
WORKDIR /tmp
RUN git clone https://github.com/samtools/htslib
WORKDIR /tmp/htslib
RUN make && make install

# install most required perl modules using cpanminus
#RUN cpanm Encode::Escape::ASCII 
RUN cpanm Scalar::Util \
        Archive::Zip \
        CGI::Session \
        Class::Accessor \
        CSS::Minifier \
        DBI \
        HTTP::Date \
        Image::Size \
        Inline IO::Scalar \
        IO::Socket \
        IO::Socket::INET \
        IO::Socket::UNIX \
        IO::String \
        List::MoreUtils \
        Mail::Mailer \
        Math::Bezier \
        MIME::Types \
        PDF::API2 \
        RTF::Writer \
        Spreadsheet::WriteExcel \
        Sys::Hostname::Long \
        Text::ParseWords \
        URI \
        URI::Escape \
        HTML::Template \
        Clone \
        Hash::Merge \
        Class::DBI::Sweet \
        Compress::Bzip2 \
        Digest::MD5 \
        File::Spec::Functions \
        HTML::Entities \
        IO::Uncompress::Bunzip2 \
        XML::Parser \
        XML::Simple \
        XML::Writer \
        SOAP::Lite \
        GD \
        GraphViz \
        String::CRC32 \
        Cache::Memcached::GetParser \
        Inline::C \
        XML::Atom \
        LWP \
        BSD::Resource \
        JSON \
        Linux::Pid \
        Readonly \
        Module::Build \
        Bio::Root::Build \
        Lingua::EN::Inflect \
        YAML \
        Math::Round \
        Rose::DB::Object::Manager \
        Tree::DAG_Node \
        IO::Unread \
        Text::LevenshteinXS \
        Math::SigFigs

# install kent utils (see https://hub.docker.com/r/genomicpariscentre/biotoolbox/~/dockerfile/ for inspiration)
WORKDIR /usr/local 
#RUN git clone git://genome-source.cse.ucsc.edu/kent.git

RUN wget http://hgdownload.cse.ucsc.edu/admin/jksrc.zip
RUN apt-get install unzip
RUN unzip jksrc.zip
RUN rm jksrc.zip

WORKDIR /usr/local/kent/src/
ENV MACHTYPE x86_64
ENV KENT_SRC /usr/local/kent/src

WORKDIR /usr/local/kent/src/inc
RUN  mkdir /usr/local/bin/script; mkdir /usr/local/bin/x86_64
RUN sed -i "s/CFLAGS\=/CFLAGS\=\-fPIC/" common.mk \
 && sed -i "s:BINDIR = \${HOME}/bin/\${MACHTYPE}:BINDIR=/usr/local/bin/\${MACHTYPE}:" common.mk \
 && sed -i "s:SCRIPTS=\${HOME}/bin/scripts:SCRIPTS=/usr/local/bin/scripts:" common.mk

WORKDIR /usr/local/kent/src/lib
RUN make

WORKDIR /usr/local/kent/src/jkOwnLib
RUN make

WORKDIR /usr/local/kent/src/htslib
RUN sed -i "s/-DUCSC_CRAM/-DUCSC_CRAM -fPIC/" Makefile
RUN make

WORKDIR /tmp
RUN wget http://cpan.metacpan.org/authors/id/L/LD/LDS/Bio-BigFile-1.07.tar.gz
RUN tar xzf Bio-BigFile-1.07.tar.gz
WORKDIR /tmp/Bio-BigFile-1.07
RUN ls -la \
 && sed -i "s/\$ENV{KENT_SRC}/\'\/usr\/local\/kent\/src\'/" Build.PL \
 && sed -i "s/\$ENV{MACHTYPE}/x86_64/" Build.PL \
 && sed -i 's:extra_linker_flags => \["\$jk_lib/\$LibFile":extra_linker_flags => \["-pthread","\$jk_lib/\$LibFile","\$jk_include/../htslib/libhts.a":' Build.PL \
# && cat Build.PL
 && perl Build.PL \
 && ./Build \
 && ./Build test \
 && ./Build install 

# install Bio::DB::HTS::Tabix using cpanminus
RUN cpanm Bio::DB::HTS::Tabix

RUN mkdir -p /ensembl

RUN adduser --disabled-password --gecos '' eguser \
    && adduser eguser sudo \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# set mysql root password without prompting
# set password with --build-args
#ARG DB_SESSION_PASSWORD
#ARG DB_ROOT_PASSWORD
#ARG ENSEMBL_VERSION
#RUN { echo mysql-server mysql-server/root_password password $DB_ROOT_PASSWORD; } | debconf-set-selections \
#    && { echo mysql-server mysql-server/root_password_again password $DB_ROOT_PASSWORD; } | debconf-set-selections \
#    && apt-get update && apt-get install -y mysql-server
#RUN echo $DB_ROOT_PASSWORD | dpkg-reconfigure mysql-server
#RUN apt-get update \
#    && apt-get install -y debconf-utils \
#    && echo mysql-server-5.5 mysql-server/root_password password xyzzy | debconf-set-selections \
#    && echo mysql-server-5.5 mysql-server/root_password_again password xyzzy | debconf-set-selections \
#    && apt-get install -y mysql-server -o pkg::Options::="--force-confdef" -o pkg::Options::="--force-confold" --fix-missing \
#    && apt-get install -y net-tools --fix-missing \
#    && apt-get install -y mysql-client mysql-common \
#    && rm -rf /var/lib/apt/lists/*

# git clone easy mirror/import
WORKDIR /ensembl
RUN git clone --recursive https://github.com/lepbase/easy-import ei
WORKDIR /ensembl/ei
RUN git checkout develop

EXPOSE 8080

RUN mkdir /ensembl/docker-scripts
WORKDIR /ensembl/docker-scripts
RUN printf "#!/bin/bash\n\ncd /ensembl/ei/em &> /ensembl/logs/testfile\n./update-ensembl-code.sh /ensembl/conf/setup.ini &> /ensembl/logs/update.log\necho 3 > testfile\n./reload-ensembl-site.sh /ensembl/conf/setup.ini &> /ensembl/logs/reload.log\ncd -\ntail -f /dev/null\n" > startup.sh \
    && chmod 755 startup.sh

RUN chown -R eguser:eguser /ensembl

# create symbolic link to perl binary in location referenced by ensembl scripts
RUN ln -s /usr/bin/perl /usr/local/bin/perl

#WORKDIR /ensembl/ei/em
#RUN service mysql stop \
#    && sed -i "s:127.0.0.1:localhost:" /etc/mysql/my.cnf \
#    && service mysql start
#RUN cat /etc/mysql/my.cnf
#RUN chmod -R 755 /var/run/mysqld
#RUN mysqladmin -uroot -p$DB_ROOT_PASSWORD status
#RUN ./setup-databases.sh /tmp/db.ini

# set up a local accounts/session database
#RUN printf "[DATABASE]\nDB_USER = anonymous\nDB_SESSION_USER = ensrw\nDB_SESSION_PASS = $DB_SESSION_PASSWORD\nDB_ROOT_USER = root\nDB_ROOT_PASSWORD = $DB_ROOT_PASSWORD\nDB_PORT = 3306\nDB_HOST = localhost\n" > /tmp/db.ini
#RUN printf "[WEBSITE]\nENSEMBL_WEBSITE_HOST = localhost\n" >> /tmp/db.ini
#RUN printf "[DATA_SOURCE]\nENSEMBL_DB_URL = ftp://ftp.ensembl.org/pub/release-$ENSEMBL_VERSION/mysql/\nENSEMBL_DB_REPLACE = 1\nENSEMBL_DBS = [ ensembl_accounts ]\n" >> /tmp/db.ini
#RUN cat /tmp/db.ini

RUN apt-get install -y nano

USER eguser
#WORKDIR /ensembl/docker-scripts
CMD ["/ensembl/docker-scripts/startup.sh"]

