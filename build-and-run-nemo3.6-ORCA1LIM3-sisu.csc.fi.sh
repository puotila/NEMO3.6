#!/bin/bash -l
#SBATCH -J nemo
#SBATCH -o nemo%J.out
#SBATCH -e nemo%J.err
#SBATCH -t 00:29:00
#SBATCH -N 1
#SBATCH -p test

# Environment setup

module load svn craypkg-gen cray-hdf5-parallel cray-netcdf-hdf5parallel xios/2.0.990

if [[ "$PE_ENV" = "GNU" ]]; then
    PE_LEVEL=5.1
fi

# Checkout sources

cd $WRKDIR
svn co http://forge.ipsl.jussieu.fr/nemo/svn/NEMO/releases/release-3.6/NEMOGCM NEMOGCM3.6

# Configure architecture

find_root () {
    local regexp="-I[^ ]*${1}[^ ]*"
    [[ $(ftn -craype-verbose 2> /dev/null) =~ $regexp ]]
    echo ${BASH_REMATCH[1]}
}

cd NEMOGCM3.6/CONFIG
cat > ../ARCH/arch-xc40-sisu.csc.fi.fcm <<EOF
%HDF5_HOME           ${HDF5_DIR}

%NCDF_HOME           ${NETCDF_DIR}
%NCDF_INC            -I%NCDF_HOME/include -I%HDF5_HOME/include
%NCDF_LIB            -L%HDF5_HOME/lib -L%NCDF_HOME/lib -lnetcdff -lnetcdf -lhdf5_hl -lhdf5 -lz

%XIOS_HOME           /appl/climate/xios/2.0.990/CRAY/8.5
#%XIOS_HOME           /appl/climate/xios/1.0.703/CRAY/8.5
%XIOS_INC            -I%XIOS_HOME/inc
%XIOS_LIB            -L%XIOS_HOME/lib -lxios

%CPP                 cpp

%FC                  ftn
%FCFLAGS             -emf -s real64 -s integer32  -O2 -hflex_mp=intolerant -Rb 
%FFLAGS              -emf -s real64 -s integer32  -O0 -hflex_mp=strict -Rb

%FPPFLAGS            -P -E -traditional-cpp

%LD                  ftn
%LDFLAGS             -hbyteswapio 

%AR                  ar
%ARFLAGS             -r

%MK                  gmake

%USER_INC            %XIOS_INC
%USER_LIB            %XIOS_LIB
EOF

# Get and set ORCA1L75LIM3 configuration without PISCES
svn -r73 --username puotila co http://forge.ipsl.jussieu.fr/shaconemo/svn/trunk/ORCA1_LIM3_PISCES/
echo "ORCA1_LIM3_PISCES OPA_SRC LIM_SRC_3 NST_SRC TOP_SRC" >> cfg.txt
echo "ORCA1_LIM3 OPA_SRC LIM_SRC_3 NST_SRC" >> cfg.txt

cp -ar ORCA1_LIM3_PISCES ORCA1_LIM3
rm ORCA1_LIM3/cpp_ORCA1_LIM3_PISCES.fcm
echo "bld::tool::fppkeys key_trabbl key_lim3 key_vvl key_dynspg_ts key_diaeiv key_ldfslp key_traldf_c2d key_traldf_eiv key_dynldf_c3d  key_zdfddm key_zdftmx_new key_mpp_mpi key_zdftke key_iomput key_mpp_rep key_xios2 key_nosignedzero" > ORCA1_LIM3/cpp_ORCA1_LIM3.fcm

# Compile executable
./makenemo -m xc40-sisu.csc.fi -n ORCA1_LIM3

# Create an experiment
rm -f ORCA1_LIM3/EXP01
mkdir ORCA1_LIM3/EXP01
cd ORCA1_LIM3/EXP01
tar -xf /wrk/puotila/DONOTREMOVE/SHACONEMO/INPUTS_ORCA1_LIM3_UH_V1.tar
ln -s ${WRKDIR}/NEMOGCM3.6/CONFIG/ORCA1_LIM3/BLD/bin/nemo.exe opa
ln -s ../../SHARED/namelist_ice_lim3_ref namelist_ice_ref
ln -s ../../SHARED/namelist_ref namelist_ref

sbatch -N 1 -p test -t 30 -J orca1 << EOF
#!/bin/bash
aprun -n 24 ./opa
EOF
