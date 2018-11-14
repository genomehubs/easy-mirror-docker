FROM ubuntu:bionic

MAINTAINER  Richard Challis/Lepbase contact@lepbase.org

ENV TERM xterm
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -y \
    acedb-other-dotter \
    build-essential \
    bzip2 \
    cpanminus \
    curl \
    freetype* \
    git \
    graphviz \
    imagemagick \
    libbz2-dev \
    libcurl4-openssl-dev \
    libdbd-mysql-perl \
    libevent-dev \
    libgd-dev \
    libgdbm-dev \
    libhts-dev \
    libhts2 \
    libio-socket-ssl-perl \
    libmemcached-dev \
    libmysqlclient*-dev \
    libdatetime-perl \
    libperl-dev \
    libwww-curl-perl \
    libssl-dev \
    libxml2-dev \
    memcachedb \
    mysql-client \
    mysql-common \
    openjdk-8-jre-headless \
    openssl \
    php-gd \
    tabix \
    vcftools \
    unzip \
    uuid-dev \
    wget && \
    rm -rf /var/lib/apt/lists/*

# accepts Microsoft EULA agreement without prompting
# view EULA at http://wwww.microsoft.com/typography/fontpack/eula.htm
RUN { echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true; } | debconf-set-selections \
    && apt-get update && apt-get install -y ttf-mscorefonts-installer

RUN export PERL5LIB=.:$PERL5LIB && \
    cpanm \
    Archive::Zip \
    BSD::Resource \
    Bio::Root::IO \
    Cache::Memcached::GetParser \
    CGI::Session \
    Class::Accessor \
    Class::DBI::Sweet \
    Clone \
    Compress::Bzip2 \
    CSS::Minifier \
    DBD::SQLite \
    DBI \
    Digest::MD5 \
    GD \
    Hash::Merge \
    HTML::Template \
    HTTP::Date \
    Image::Size \
    Inline \
    Inline::C \
    IO::Scalar \
    IO::String \
    IO::Uncompress::Bunzip2 \
    JSON \
    JSON::PP \
    JSON::Parse \
    Lingua::EN::Inflect \
    Linux::Pid \
    List::MoreUtils \
    LWP \
    Math::Bezier \
    Math::Round \
    MIME::Types \
    PDF::API2 \
    Readonly \
    Role::Tiny \
    Rose::DB::Object::Manager \
    RTF::Writer \
    Spreadsheet::WriteExcel \
    String::CRC32 \
    Sys::Hostname::Long \
    Text::CSV \
    Text::ParseWords \
    URI \
    WWW::Curl::Multi \
    XML::Atom \
    YAML

WORKDIR /tmp

RUN wget -q http://archive.apache.org/dist/httpd/CHANGES_2.2 \
    && export APACHEVERSION=`grep "Changes with" CHANGES_2.2 | head -n 1 | cut -d" " -f 4` \
    && wget -q http://archive.apache.org/dist/httpd/httpd-$APACHEVERSION.tar.gz \
    && tar xzf httpd-$APACHEVERSION.tar.gz \
    && cd httpd-$APACHEVERSION \
    && ./configure --with-included-apr --enable-deflate --enable-headers --enable-expires --enable-rewrite --enable-proxy \
    && make && make install

# install the latest version of mod_perl
RUN wget -q -O tmp.html http://www.cpan.org/modules/by-module/Apache2/ \
    && MODPERLTAR=`grep -oP "mod_perl.*?tar" tmp.html | sort -Vr | head -n 1` \
    && MODPERLVERSION=${MODPERLTAR%.*} \
    && wget http://www.cpan.org/modules/by-module/Apache2/$MODPERLVERSION.tar.gz \
    && tar xzf $MODPERLVERSION.tar.gz \
    && cd $MODPERLVERSION \
    && perl Makefile.PL MP_APXS=/usr/local/apache2/bin/apxs \
    && make && make install

RUN git clone https://github.com/samtools/tabix && \
    cd tabix/perl && \
    perl Makefile.PL && \
    make && \
    make install

RUN git clone https://github.com/samtools/htslib && \
    cd htslib && \
    make && \
    make install

RUN cpanm \
    Bio::DB::HTS \
    Bio::DB::HTS::Tabix

# install kent utils (see https://hub.docker.com/r/genomicpariscentre/biotoolbox/~/dockerfile/ for inspiration)
ENV MACHTYPE x86_64
ENV KENT_SRC /usr/local/kent/src
WORKDIR /usr/local
RUN wget http://hgdownload.cse.ucsc.edu/admin/jksrc.zip && \
    unzip jksrc.zip && \
    rm jksrc.zip && \
    cd kent/src/inc && \
    mkdir /usr/local/bin/script && \
    mkdir /usr/local/bin/x86_64 && \
    sed -i "s/CFLAGS\=/CFLAGS\=\-fPIC/" common.mk && \
    sed -i "s:BINDIR = \${HOME}/bin/\${MACHTYPE}:BINDIR=/usr/local/bin/\${MACHTYPE}:" common.mk && \
    sed -i "s:SCRIPTS=\${HOME}/bin/scripts:SCRIPTS=/usr/local/bin/scripts:" common.mk && \
    cd ../lib && \
    make && \
    cd ../jkOwnLib && \
    make && \
    cd ../htslib && \
    sed -i "s/-DUCSC_CRAM/-DUCSC_CRAM -fPIC/" Makefile && \
    make

WORKDIR /tmp

RUN wget http://cpan.metacpan.org/authors/id/L/LD/LDS/Bio-BigFile-1.07.tar.gz && \
    tar xzf Bio-BigFile-1.07.tar.gz && \
    cd Bio-BigFile-1.07 && \
    sed -i "s/\$ENV{KENT_SRC}/\'\/usr\/local\/kent\/src\'/" Build.PL && \
    sed -i "s/\$ENV{MACHTYPE}/x86_64/" Build.PL && \
    sed -i 's:extra_linker_flags => \["\$jk_lib/\$LibFile":extra_linker_flags => \["-pthread","\$jk_lib/\$LibFile","\$jk_include/../htslib/libhts.a":' Build.PL && \
    perl Build.PL && \
    ./Build && \
    ./Build test && \
    ./Build install

RUN adduser --disabled-password --gecos '' eguser

RUN mkdir -p /ensembl && \
    mkdir -p /ensembl/logs && \
    mkdir -p /ensembl/tmp && \
    mkdir -p /ensembl/scripts && \
    mkdir -p /ensembl/conf && \
    chown -R eguser:eguser /ensembl && \
    mkdir -p /conf && \
    chown -R eguser:eguser /conf

EXPOSE 8080

USER eguser
COPY update.sh /ensembl/scripts/
COPY default.setup.ini /conf/setup.ini
COPY default.database.ini /conf/database.ini
RUN /ensembl/scripts/update.sh /conf/setup.ini
ENV PERL5LIB $PERL5LIB:/ensembl/bioperl-live\
:/ensembl/ensembl/modules\
:/ensembl/ensembl-compara/modules\
:/ensembl/ensembl-funcgen/modules\
:/ensembl/ensembl-io/modules\
:/ensembl/ensembl-variation/modules

COPY httpd.conf /ensembl/scripts/
COPY *.sh /ensembl/scripts/
COPY *.png /ensembl/scripts/

WORKDIR /ensembl

CMD ["/ensembl/scripts/startup.sh"]
