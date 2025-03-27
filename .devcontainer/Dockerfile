# Copyright (c) 2024-2025 fei_cong(https://github.com/feicong/ebpf-course)
FROM mcr.microsoft.com/devcontainers/base:jammy
LABEL maintainer=feicong

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ="Asia/Shanghai"

COPY build.sh /build.sh
RUN bash /build.sh && rm /build.sh

RUN apt clean \
    && rm -rf /var/lib/apt/lists/*

CMD ["bash"]
