FROM nvidia/cuda:11.1.1-cudnn8-devel-ubuntu20.04

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get install -y \
    python3-opencv ca-certificates python3.8 python3.8-dev git wget sudo ninja-build python3-distutils && \
    ln -fsv /usr/bin/python3.8 /usr/bin/python3

# create a non-root user
ARG USER_ID=1000
RUN useradd -m --no-log-init --system --uid ${USER_ID} appuser -g sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER appuser
WORKDIR /home/appuser

ENV PATH="/home/appuser/.local/bin:${PATH}"
RUN wget https://bootstrap.pypa.io/get-pip.py && \
    python3 get-pip.py --user && \
    rm get-pip.py

# install dependencies
RUN pip install --user tensorboard cmake onnx
RUN pip install --user torch==1.10 torchvision==0.11.1 -f https://download.pytorch.org/whl/cu111/torch_stable.html

RUN pip install --user 'git+https://github.com/facebookresearch/fvcore'
# install detectron2
RUN git clone https://github.com/facebookresearch/detectron2 detectron2_repo
ENV FORCE_CUDA="1"
ARG TORCH_CUDA_ARCH_LIST="Kepler;Kepler+Tesla;Maxwell;Maxwell+Tegra;Pascal;Volta;Turing"
ENV TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST}"

RUN pip install --user -e detectron2_repo

# Set a fixed model cache directory.
ENV FVCORE_CACHE="/tmp"
WORKDIR /home/appuser/detectron2_repo

# run detectron2 under user "appuser":
RUN pip install --user \
    pillow==10.4.0 \
    numpy==1.24.4 \
    opencv-python==4.10.0.84 \
    fastapi==0.115.4 \
    pydantic==2.9.2 \
    pydantic-settings==2.6.0 uvicorn==0.32.0 python-multipart==0.0.17

COPY ./app /home/appuser/detectron2_repo/app
COPY ./config.yml /home/appuser/detectron2_repo/config.yml
COPY ./model_final.pth /home/appuser/detectron2_repo/model_final.pth

ENTRYPOINT ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
