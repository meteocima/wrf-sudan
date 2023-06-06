#!/bin/bash

SUDAN_HOME=~/repos/wrf-sudan
GFS_DIR=$SUDAN_HOME/gfs/
WPS_HOME=$SUDAN_HOME/prg/WPS
WRF_HOME=$SUDAN_HOME/prg/WRF
RESULT_DIR=$SUDAN_HOME/results
WPS_WORKDIR=$SUDAN_HOME/workdir/wps
WRF_WORKDIR=$SUDAN_HOME/workdir/wrf
#
DT_BEG=$(date -u +"%Y-%m-%d_00:00:00")
DT_BEG_YEAR=${DT_BEG:0:4}
DT_BEG_MONTH=${DT_BEG:5:2}
DT_BEG_DAY=${DT_BEG:8:2}
#
DT_END=$(date -u -d "+ 3 days" +"%Y-%m-%d_00:00:00")
DT_END_YEAR=${DT_END:0:4}
DT_END_MONTH=${DT_END:5:2}
DT_END_DAY=${DT_END:8:2}
#
REMOTE_SERVER=wrfprod@130.251.104.19
REMOTE_BASEDIR=/share/archivio/experience/data/MeteoModels/SUDAN
REMOTE_PATH=$REMOTE_BASEDIR/$DT_BEG_YEAR/$DT_BEG_MONTH/$DT_BEG_DAY/0000
FILE_NAME=sudan-d01-${DT_BEG}UTC.nc
LOCAL_PATH=$RESULT_DIR/$FILE_NAME

export LD_LIBRARY_PATH=$SUDAN_HOME/lib:$LD_LIBRARY_PATH
export PATH=$SUDAN_HOME/bin:$PATH
ulimit -s unlimited

# echo SUDAN_HOME=$SUDAN_HOME
# echo GFS_DIR=$GFS_DIR
# echo WPS_HOME=$WPS_HOME
# echo WRF_HOME=$WRF_HOME
# echo RESULT_DIR=$RESULT_DIR
# echo WPS_WORKDIR=$WPS_WORKDIR
# echo WRF_WORKDIR=$WRF_WORKDIR
# echo DT_BEG=$DT_BEG
# echo DT_BEG_YEAR=$DT_BEG_YEAR
# echo DT_BEG_MONTH=$DT_BEG_MONTH
# echo DT_BEG_DAY=$DT_BEG_DAY
# echo DT_END=$DT_END
# echo DT_END_YEAR=$DT_END_YEAR
# echo DT_END_MONTH=$DT_END_MONTH
# echo DT_END_DAY=$DT_END_DAY
# echo REMOTE_SERVER=$REMOTE_SERVER
# echo REMOTE_BASEDIR=$REMOTE_BASEDIR
# echo REMOTE_PATH=$REMOTE_PATH
# echo FILE_NAME=$FILE_NAME
# echo LOCAL_PATH=$LOCAL_PATH
# exit 0

echo Build WPS workdir

rm -rf $WPS_WORKDIR
rm -rf $WRF_WORKDIR
rm -rf $GFS_DIR
mkdir -p $WPS_WORKDIR
mkdir -p $WRF_WORKDIR
mkdir -p $GFS_DIR

NML_WPS=$WPS_WORKDIR/namelist.wps
NML_WRF=$WPS_WORKDIR/namelist.input
cp $SUDAN_HOME/cfg/namelist.wps $NML_WPS
cp $SUDAN_HOME/cfg/namelist.input $NML_WRF

sed -i 's@$dateBeg@'"$DT_BEG"'@g' $NML_WPS
sed -i 's@$dateEnd@'"$DT_END"'@g' $NML_WPS
sed -i 's@$dateBegY@'"$DT_BEG_YEAR"'@g' $NML_WRF
sed -i 's@$dateBegM@'"$DT_BEG_MONTH"'@g' $NML_WRF
sed -i 's@$dateBegD@'"$DT_BEG_DAY"'@g' $NML_WRF
sed -i 's@$dateEndY@'"$DT_END_YEAR"'@g' $NML_WRF
sed -i 's@$dateEndM@'"$DT_END_MONTH"'@g' $NML_WRF
sed -i 's@$dateEndD@'"$DT_END_DAY"'@g' $NML_WRF

DT_FORE=$DT_BEG_YEAR$DT_BEG_MONTH$DT_BEG_DAY
echo download gfs. log in gfs.log
$SUDAN_HOME/bin/gfsdn -c $SUDAN_HOME/cfg/gfs.toml -o $SUDAN_HOME/gfs sudan 72 ${DT_FORE}00 > gfs.log 2>&1 &
cd $WPS_WORKDIR

ln -s $WPS_HOME/*.exe .
ln -s $WPS_HOME/util/avg_tsfc.exe .
ln -s $WPS_HOME/ungrib/Variable_Tables/Vtable.GFS Vtable
ln -s $WRF_HOME/run/real.exe .

echo run geogrid. log in geogrid.log
mpiexec -n 36 ./geogrid.exe > geogrid.log 2>&1 &

wait

$WPS_HOME/link_grib.csh $GFS_DIR/$DT_BEG_YEAR/$DT_BEG_MONTH/$DT_BEG_DAY/0000/sudan/*

echo run ungrib. log in ungrib.log
./ungrib.exe > ungrib.log 2>&1
echo run avg_tsfc. log in avg_tsfc.log
./avg_tsfc.exe > avg_tsfc.log 2>&1

echo run metgrid. log in metgrid.log
mpiexec -n 24 ./metgrid.exe > metgrid.log 2>&1 

echo run real. log in real.log
mpiexec -n 24 ./real.exe > real.log 2>&1  

echo build WRF workdir. 

# UPLOAD NAMELIST E CONDITIONS
cp wrf[bi]* namelist.input $WRF_WORKDIR

cd $WRF_WORKDIR

ln -s $WRF_HOME/main/wrf.exe .
ln -s $WRF_HOME/run/LANDUSE.TBL .
ln -s $WRF_HOME/run/ozone_plev.formatted .
ln -s $WRF_HOME/run/ozone_lat.formatted .
ln -s $WRF_HOME/run/ozone.formatted .
ln -s $WRF_HOME/run/RRTMG_LW_DATA .
ln -s $WRF_HOME/run/RRTMG_SW_DATA .
ln -s $WRF_HOME/run/VEGPARM.TBL .
ln -s $WRF_HOME/run/SOILPARM.TBL .
ln -s $WRF_HOME/run/GENPARM.TBL .

echo run WRF. log in wrf.log
mpirun -n 128 ./wrf.exe > wrf.log 2>&1  

cd $WRF_WORKDIR

RH_EXPR="RH2=100*(PSFC*Q2/0.622)/(611.2*exp(17.67*(T2-273.15)/((T2-273.15)+243.5)))"
RAINSUM_EXPR="RAINSUM=RAINNC+RAINC"

rm -rf $RESULT_DIR
mkdir -p $RESULT_DIR

echo Postprocess. log in postprocess.log

echo Fix date time
for f in $WRF_WORKDIR/auxhist23_d01_*; do
   date=$(basename $f | cut -c 15-24)
   time=$(basename $f | cut -c 26-34)
   echo Fixing time for $(basename $f)
   cdo -b F64 -O settaxis,$date,$time $f $(basename ${f}).fixdate >> postprocess.log 2>&1
done

echo Merge hourly files into a single one
cdo -O -v mergetime *.fixdate sudan-dtfrm.nc >> postprocess.log 2>&1
cdo -O -setreftime,'2000-01-01','00:00:00' sudan-dtfrm.nc sudan.nc >> postprocess.log 2>&1

echo Remove wrong variables
ncks -O -x -v P_PL,C1H,C2H,C3H,C4H,C1F,C2F,C3F,C4F,GHT_PL,Q_PL,RH_PL,S_PL,TD_PL,T_PL,U_PL,V_PL,EMISS,GLW,GRDFLX,HFX,UST,ZNT sudan.nc clean-sudan.nc >> postprocess.log 2>&1

echo Regridding
cdo -O remapbil,$SUDAN_HOME/cfg/cdo_wrfsudan_d01_grid.txt clean-sudan.nc rg-sudan.nc >> postprocess.log 2>&1

echo Calculating RH_EXPR
cdo -O -setrtoc,100,1.e99,100 -setunit,"%" -expr,$RH_EXPR rg-sudan.nc rh-sudan.nc >> postprocess.log 2>&1

echo Calculating RAINSUM_EXPR
cdo -O -setrtoc,100,1.e99,100 -setunit,"%" -expr,$RAINSUM_EXPR rg-sudan.nc rainsum-sudan.nc >> postprocess.log 2>&1

echo Merging new variables with main file
cdo -O -v -f nc4c -z zip9 merge rg-sudan.nc rainsum-sudan.nc rh-sudan.nc $RESULT_DIR/sudan-d01-${DT_BEG}UTC.nc >> postprocess.log 2>&1

echo Uploading to Dewetra
#ssh -i ~/.ssh/id_rsa.dewetra $REMOTE_SERVER mkdir -p $REMOTE_PATH
#scp -i ~/.ssh/id_rsa.antonio $LOCAL_PATH $REMOTE_SERVER:$REMOTE_PATH/$FILE_NAME.tmp
#ssh -i ~/.ssh/id_rsa.antonio $REMOTE_SERVER mv $REMOTE_PATH/$FILE_NAME.tmp $REMOTE_PATH/$FILE_NAME

echo Done
