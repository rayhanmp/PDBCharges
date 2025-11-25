# Stage 1: Build stage
FROM python:3.11-slim AS build

## Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Set a working directory for building
WORKDIR /opt/PDBCharges

# Install system dependencies for building
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  cmake \
  wget \
  curl \
  gfortran \
  git \
  libopenblas-dev \
  liblapack-dev \
  libeigen3-dev \
  libx11-dev \
  libglu1-mesa-dev \
  libxi-dev \
  libxrandr-dev \
  libxcursor-dev \
  libxtst-dev \
  zlib1g-dev \
  openbabel \
  && rm -rf /var/lib/apt/lists/*

ENV MAMBA_ROOT_PREFIX=/opt/conda
ENV PATH=$MAMBA_ROOT_PREFIX/bin:$PATH

# Download and install Micromamba
RUN curl -L https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xvj bin/micromamba && \
  mkdir -p /opt/conda/pkgs

# We install python, rdkit, pandas, dimorphite-dl, and libstdcxx-ng
RUN ./bin/micromamba create -y -p /opt/conda/envs/base -c conda-forge \
  python=3.11 \
  rdkit=2023.09.6 \
  openmm=8.2.0 \
  pandas \
  dimorphite-dl=1.3.2 \
  libstdcxx-ng \
  && rm -rf /root/.cache bin/micromamba

# Activate the Conda environment
# This ensures that 'pip' and 'python' commands below use the Conda env.
ENV PATH="/opt/conda/envs/base/bin:$PATH"

# Install Python dependencies
RUN pip install --no-cache-dir \
  hydride==1.2.3 \
  biopython==1.84 \
  numpy==1.26.4 \
  biotite==1.0.1 \
  gemmi==0.6.6 \
  moleculekit==1.9.15 \
  pdb2pqr==3.6.1

# Install xtb 6.6.1
RUN curl -L https://github.com/grimme-lab/xtb/releases/download/v6.6.1/xtb-6.6.1-source.tar.xz | tar xJ \
  && cd xtb-6.6.1 \
  && mkdir build && cd build \
  && cmake .. \
  && make -j$(nproc) \
  && make install \
  && cd ../.. && rm -rf xtb-6.6.1

# Install pdbfixer
RUN git clone https://github.com/openmm/pdbfixer.git /opt/pdbfixer \
  && cd /opt/pdbfixer \
  && git config --global advice.detachedHead false \
  && git checkout c83d125f445d3cea414203d48e4438c6033aaec6 \
  && pip install . \
  && cd / && rm -rf /opt/pdbfixer

# Get sources
COPY calculate_charges_workflow.py .
COPY phases phases
COPY docker docker

# Apply modifications to moleculekit (Using the Conda path)
RUN python3 docker/edit_moleculekit.py /opt/conda/envs/base/lib/python3.11/site-packages/moleculekit/tools/preparation.py

### Stage 2: Runtime stage
FROM python:3.11-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

# Set PATH to prefer Conda bin. 
ENV PATH="/opt/PDBCharges:/opt/conda/envs/base/bin:$PATH"

# Set LD_LIBRARY_PATH so system tools can find Conda's C++ libraries
ENV LD_LIBRARY_PATH="/opt/conda/envs/base/lib:$LD_LIBRARY_PATH"

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  libopenblas0 \
  libgfortran5 \
  openbabel \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

## Copy artefacts
COPY --from=build /opt/conda /opt/conda
COPY --from=build /usr/local/bin/xtb /usr/local/bin/
COPY --from=build /usr/local/lib/libxtb.so* /usr/local/lib/
COPY --from=build /usr/local/share/xtb /usr/local/share/xtb
COPY --from=build /opt/PDBCharges /opt/PDBCharges

# Set the working directory
WORKDIR /opt/PDBCharges

# Create a user and set permissions
RUN useradd --create-home --shell /bin/bash user \
  && chown -R user:user /opt \
  && chmod u+x calculate_charges_workflow.py

# Switch to the user
USER user

CMD ["python", "calculate_charges_workflow.py"]