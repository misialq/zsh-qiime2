### Functions

function current_q2_version() {
  QIIME_INFO=$(qiime info) 2>/dev/null
  if [[ $? == 0 ]]; then
    QIIME2_VERSION=$(echo "$QIIME_INFO" | grep "QIIME 2 version" | sed "s/QIIME 2 version\://" | xargs)
    QIIME2_RELEASE=$(echo "$QIIME_INFO" | grep "QIIME 2 release" | sed "s/QIIME 2 release\://" | xargs)
  else
    QIIME2_VERSION=""
    QIIME2_RELEASE=""
  fi

  if [[ $QIIME2_VERSION == *dev* ]]; then
    QIIME2_RELEASE="Q2:${QIIME2_RELEASE}(dev)"
  elif [[ $QIIME2_VERSION != "" ]]; then
    QIIME2_RELEASE="Q2:${QIIME2_RELEASE}"
  else
    QIIME2_RELEASE=""
  fi

  echo "$QIIME2_RELEASE"
}

function prompt_qiime2() {
  current_q2_version >/dev/null
  p10k segment -t "${QIIME2_RELEASE}" -f 121
}

function get_latest_q2_dev_version() {
  latest_q2_tag=$(git ls-remote --tags --refs --sort 'v:refname' https://github.com/qiime2/qiime2.git | tail -1)
  QIIME2_LATEST_DEV_VERSION=$(echo $latest_q2_tag | sed 's/.*tags\///' | xargs)
  QIIME2_LATEST_DEV_RELEASE=$(echo $QIIME2_LATEST_DEV_VERSION | sed 's/\.[0-9]*\.dev.*$//' | xargs)
}

function get_latest_q2_prod_version() {
  latest_q2_tags=($(git ls-remote --tags --refs --sort '-v:refname' https://github.com/qiime2/qiime2.git | sed 's/.*tags\///'))
  for tag in $latest_q2_tags; do
    if [[ $tag == *dev* ]]; then
      continue
    else
      QIIME2_LATEST_PROD_RELEASE=$(echo "$tag" | xargs)
      break
    fi
  done
}

function extend_env() {
  CONDA_INFO=$(conda info)
  CONDA_ENVS=$(echo "$CONDA_INFO" | grep "envs directories" | sed "s/envs directories \: //" | xargs)
  CONDA_MAIN=$(echo $CONDA_ENVS | sed "s/\/envs//")
  CONDA_CURRENT_ENV=$(echo "$CONDA_INFO" | grep "active environment" | sed "s/active environment \: //" | xargs)
  CONDA_CURRENT_ENV_LOC=$(echo "$CONDA_INFO" | grep "active env location" | sed "s/active env location \: //" | xargs)

  conda install -qy flake8 coverage wget pytest-xdist
  python -m pip install -q https://github.com/qiime2/q2lint/archive/master.zip
}

function set_up_dev_env() {
  get_latest_q2_dev_version
  QIIME2_DEV_CHANNEL="https://packages.qiime2.org/qiime2/${QIIME2_LATEST_DEV_RELEASE}/staged"
  ENV_NAME="$1"
  COL="\033[0;32m"
  NC="\033[0m"

  if [[ "${ENV_NAME}" == "" ]]; then
    ENV_NAME="qiime2-${QIIME2_LATEST_DEV_RELEASE}"
  fi

  echo "${COL}Creating conda environment (${ENV_NAME}) for QIIME 2 ${QIIME2_LATEST_DEV_VERSION}...${NC}"
  conda deactivate
  conda create -y -n "${ENV_NAME}" \
    -c "${QIIME2_DEV_CHANNEL}" -c conda-forge -c bioconda -c defaults \
    qiime2 q2cli q2-types click==7.1.2

  conda activate "$ENV_NAME"
  extend_env

  unset COL
  unset NC
  unset ENV_NAME
}

function set_up_full_env() {
  ENV_NAME="$1"
  COL="\033[0;32m"
  RED="\033[0;31m"
  NC="\033[0m" # NoColor

  if [[ "$OSTYPE" == "linux"* ]]; then
    OS_VER="linux"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS_VER="osx"
  else
    echo "${RED}Detected OS version (${OSTYPE}) is not supported.${NC}"
    echo "${RED}Aborting.${NC}"
    return 1
  fi

  get_latest_q2_prod_version
  echo "${COL}The latest available QIIME2 version is ${QIIME2_LATEST_PROD_RELEASE}.${NC}"

  VER_SHORT=$(echo "${QIIME2_LATEST_PROD_RELEASE}" | sed 's/\.[0-9]$//' | xargs)
  if [[ "${ENV_NAME}" == "" ]]; then
    ENV_NAME="qiime2-${VER_SHORT}"
  fi
  echo "${COL}Creating a full ${ENV_NAME} environment...${NC}"

  DOWNLOAD_LINK="https://data.qiime2.org/distro/core/qiime2-${VER_SHORT}-py38-${OS_VER}-conda.yml"
  ENV_FILE="env-spec-${VER_SHORT}.yaml"
  curl -sL "${DOWNLOAD_LINK}" -o "${ENV_FILE}"
  conda env create -n "${ENV_NAME}" --file "${ENV_FILE}"
  rm "${ENV_FILE}"

  conda activate "${ENV_NAME}"

  unset COL
  unset NC
  unset RED
}

function build_conda_pkg() {
  # first arg should be name of the package to be built
  # second arg should be Q2 version to test against (e.g. 2021.8)
  # third arg should be OS version (osx or linux)
  PKG_NAME="$1"
  if test "PKG_NAME" = ""; then
    echo "${RED}Name of the to-be-built package is required.${NC}"
    echo "${RED}Build aborted.${NC}"
    return 1
  fi
  PKG_NAME_UNDER="${PKG_NAME//-/_}"

  Q2V="$2"
  OSV="$3"
  COL="\033[0;32m"
  RED="\033[0;31m"
  NC="\033[0m" # NoColor

  if test "$Q2V" = ""; then
    Q2V="2021.8"
  fi

  if test "$OSV" = ""; then
    OSV="osx"
  fi

  # check that required files exist
  if ! test -f "conda_build_config.yaml" || ! test -f "meta.yaml"; then
    echo "${RED}One of the required files (conda_build_config.yaml or meta.yaml) could not be found.${NC}"
    echo "${RED}Build aborted.${NC}"
    return 1
  fi

  conda deactivate
  CONDA_ENVS=$(conda info | grep "envs directories" | sed "s/envs directories \: //" | xargs)
  CONDA_MAIN=$(echo $CONDA_ENVS | sed "s/\/envs//")
  echo "${COL}Detected conda path: ${CONDA_MAIN}${NC}"

  echo "${COL}Preparing a new conda environment (qiime2-${Q2V}-buildtest)...${NC}"
  conda create -y -n "qiime2-${Q2V}-buildtest" conda-build conda-verify wget
  source "${CONDA_MAIN}/etc/profile.d/conda.sh"
  conda activate "qiime2-${Q2V}-buildtest"
  conda info

  # build new package
  echo "${COL}Starting build for QIIME2 ${Q2V} (${OSV})...${NC}"
  conda build -c "https://packages.qiime2.org/qiime2/${Q2V}/staged" -c conda-forge -c bioconda -c defaults --override-channels --no-anaconda-upload --cache-dir conda_cache .

  # test the build
  echo "${COL}Testing the build...${NC}"
  wget -O env.yml "https://raw.githubusercontent.com/qiime2/environment-files/master/${Q2V}/staging/qiime2-${Q2V}-py38-${OSV}-conda.yml"
  conda env create -q -p "./testing-${Q2V}" --file env.yml
  conda install -p "./testing-${Q2V}" -q -y -c "$CONDA_MAIN/conda-bld/${OSV}-64" -c conda-forge -c bioconda -c defaults --override-channels --strict-channel-priority "${PKG_NAME}"

  conda activate "./testing-${Q2V}"
  pytest --pyargs "${PKG_NAME_UNDER}"
  conda deactivate

  # clean up previous build tests
  echo "${COL}Cleaning up...${NC}"
  rm -rf "./testing-${Q2V}/*"
  rm env.yml
  conda build purge

  conda deactivate
  conda env remove -n "qiime2-${Q2V}-buildtest"

  echo "${COL}All done!${NC}"

}

### Aliases

alias q2='qiime'
alias q2cit='qiime tools citations'
alias q2xt='qiime tools extract'
alias q2xp='qiime tools export'
alias q2i='qiime tools import'
alias q2it='qiime tools import --show-importable-types'
alias q2if='qiime tools import --show-importable-formats'
alias q2rc='qiime dev refresh-cache'
alias q2p='qiime tools peek'
alias q2v='qiime tools view'
alias q2val='qiime tools validate'
alias q2ins='qiime tools inspect-metadata'
alias piqr='pip install . && qiime dev refresh-cache'
