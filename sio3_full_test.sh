#!/usr/bin/env bash
# Functional Test SIO3
#Script for Testing SIO standard registers, test register, OneWire ID and LEMO Registers
#K. Kaiser Vers.1 2015-08-26
#H. Becht  Vers.2 2017.05.02: new surface and testing-routines with dialog
#H. Becht  Vers.2.1 2018.01.16: testing routine for new Mil-Makro (Retrofitting)

clear

# Parameter check
#----------------
if [ $# -ne 3 ]
then
  if [ $# -lt 3 ]
  then
    echo "Fehler: erwarte Argumente!"
  else
    echo "Fehler: zu viele Argumente!"
  fi
  echo -e "\nBsp.: \e[7m $0 0022 5500230001 Mueller \e[0m"
  echo -e "(0022 für scuxl0022), CID, (Nachname oder Kuerzel)\n\n"
  exit 1
fi


################################################################################
# Initialisierung
################################################################################
# Adressen
scu_vendor_id='0x651' # GSI => aus mini_sdb.h
scu_bus_master_dev_id='0x9602eb6f' # aus mini_sdb.h

# globale Variablen
cid_id="$2"
scuname="scuxl$1"
lastname="$3"
date=$(date +%Y-%m-%d)
scutcp="tcp/$scuname.acc"

#Files
sculog="./scu_sio3_$cid_id.log";    # Log-Datei fuer den Test
onwireidfile="./1W_SIO3_$cid_id.txt"; # Log-Datei für die ausgelesene One-Wire ID
hlpfile="./hlp/sio3.hlp";   # Textdatei fuer Hilfeseiten

#Temp-Files
tmpfile="/tmp/data.tmp";    # Temp-Datei fuer div. Aufgaben
tmp2file="/tmp/data2.tmp";  # Temp-Datei fuer div. Aufgaben
countfile="/tmp/count.tmp"; # Fehlercounter fuer Subshell
summary="/tmp/sum.tmp";     # Statistik fuer Testabschluss
errlog="/tmp/$scuname.err"; # Log-Datei fuer den Fehlerkanal

slotnr="--"
typeset -i snr=0; #Seitennummer

# Konstanten
readonly REG_VAL=0x0045; #SIO3 - CID Group
typeset -i readonly CID_GR_ADR=0xA; #CID Group
typeset -i readonly SALL=20
typeset -i readonly DIABORDER=4; #Rand für Dialogfenster
readonly PAT1=0xAAAA; #Testcode fuer Echoregister
readonly PAT2=0x5555; #Testcode fuer Echoregister


# Dateien anlegen, bzw. vorbereiten, 1 Zeile leer - Abstand für Anzeige in Dialog besser
echo " " > $sculog
echo " " > $errlog

echo " " > $tmpfile
echo " " > $tmp2file
echo " " > $countfile
echo " " > $summary


# Definiere die Dialog exit status codes
: ${D_OK=0}
: ${D_CANCEL=1}
: ${D_HELP=2}
: ${D_EXTRA=3}
: ${D_ITEM_HELP=4}
: ${D_ESC=255}


#Funktion zur Anzeige des uebergebenen Help-Files
HLP() {
  local hlptxt=$1
  local ub=$2
  if [ -f "$hlpfile" ];then
    # suche und berechne den Textabschnitt der uebergebenen Hilfeseite
    #typeset -i znr_anf=$(grep -n "#Seite_$hlptxt" $hlpfile | grep -o -E "^[0-9]|[0-9]{2}"$(+1
    #typeset -i znr_end=$(grep -n "#Seite_$(( $hlptxt+1 ))" $hlpfile | grep -o -E "^[0-9]|[0-9]{2}"$(-2
    typeset -i local znr_anf=$(grep -n "$hlptxt>>>" $hlpfile | grep -o -E "^[0-9]|[0-9]{2}")+1
    typeset -i local znr_end=$(grep -n "<<<$hlptxt" $hlpfile | grep -o -E "^[0-9]|[0-9]{2}")-1

    $DIAL "$BT"\
    --title "Hilfe zu \"$ub\""\
    --ok-label "Zurueck"\
    --no-collapse\
    --msgbox "$(sed -n $znr_anf,${znr_end}p $hlpfile)" 0 0
  else
    $DIAL "$BT"\
    --title "\Zb\Z1 Fehler: Hilfe-Datei"\
    --ok-label "Zurueck"\
    --msgbox "\n${hlpfile} nicht gefunden!" 0 0
  fi
}

#Fuehrt einen Ping aus und prueft das Ergebnis auf einen String
#Dieses up wird jedesmal vor einer Verbindung ausgefuehrt
PINGCHECK() {
  if ping -c 1 -W 1 $scuname.acc > $errlog; then return 0; else return 1;fi
  # ping -O -c 1 scuxl0108.acc
}


#Funktion zum Beenden des Scriptes und Anzeige des Logfiles
#FIN <0/1>
#0: Erfolgreich beenden, 1:Vorzeitiger Abbruch
FIN() {
  if [ $1 -eq 0 ];then local grund="Pruefung vollständig durchlaufen"
  else local grund="Pruefung vorzeitig abgebrochen";fi
  { FLINE 2 "~" 80 0;FLINE 1 "~" 80 1;echo -e "$grund !!!"
    FLINE 0 "~" 80 0;FLINE 1 "~" 80 2;
  } >> $sculog

  FLINE 0 "-" 80 3 >> $summary
  cat $sculog > $tmpfile
  cat $summary > $sculog
  cat $tmpfile >> $sculog

  rm -f $summary
  rm -f $tmpfile
  rm -f $tmp2file
  rm -f $countfile
  rm -f $errlog

  $DIAL "$BT" \
  --title "  SIO3     $grund: Anzeige des LOG-File " \
  --exit-label "Beenden" \
  --textbox $sculog 0 0
  dialog --clear
  clear
  setterm -default
  setterm -clear all

  if [ $1 -eq 0 ];then exit 0;else exit 1;fi
}

#Funktion zum Erzeugen einer Linie in log-Datei
#FLINE <Abstand vor Linie> <"Zeichen(folge)"> <Anzahl Zeichen(folge)> <Abstand nach Linie>
FLINE() {
  unset vor
  unset char
  unset nach
  for ((ix=1;ix<=$1;ix++)) do vor+='\n';done
  for ((ix=1;ix<=$3;ix++)) do char+=$2;done
  for ((ix=1;ix<=$4;ix++)) do nach+='\n';done
  printf "$vor%s$nach" "$char"
}

#Funktion zum Ermitteln der Laenge des laengsten Eintrages in einem Array
MAXLENENTRY(){
  local max=0
  local arr=("${!1}");#uebernehme arrays
  local len=${#arr[*]}
  for ((ix=0;ix<len;ix++));do
    local lenentry=${#arr[$ix]}
    if [ $max -lt $lenentry ];then max=$lenentry;fi
  done
  echo $max;
}

#Funktion für Fehlerausgabe
ERRMESSAGE() {

  # Fuege eine Leerzeile am Anfang der Textdatei ein, wenn nicht vorhanden
  if ! sed '/^$/Q; Q1' $errlog; then sed -i '1 i\ ' $errlog;fi

  $DIAL "$BT" \
  --ok-label "WIEDERHOLEN" \
  --title "\Z1\Zb     FEHLER in \"$1\" " \
  --extra-button --extra-label "BEENDEN" \
  --textbox $errlog 0 0
  if [ $? -eq $D_OK ];then return
  else
    { echo -e "\n\nFEHLER in \"$1\":";FLINE 0 "#" 80 1
      cat $errlog;FLINE 1 "#" 80 0; } >> $sculog
      FIN 1
  fi
}


# Subst. f. dialog
BT="";#Global Variable
BT0="------ Funktionstest SIO3 ------"
DIAL='dialog --colors --no-shadow --backtitle'

# Funktion, um die Titelzeile auf Bildschirmgröße zu formatieren
# 1: Seitenzähler um $1 inkrementieren
# 0 oder kein Argument: Seitenzähler bleibt auf Wert
CHECKSCREEN () {
  snr=$snr+$1
  local zeilenbreite=$(tput cols); # Breite des Fensters
  local spacepost=$(((zeilenbreite-2-${#BT0})/2))
  local space=$spacepost-12
  if [ $snr -lt 10 ];then spaceafter=$((spacepost-10))
else spaceafter=$((spacepost-11));fi
  BT="Testslot: $slotnr$(FLINE 0 " " $space 0)\Z7\Zb$BT0$(FLINE 0 " " $spaceafter 0)\ZnSeite $snr/$SALL"
}

CENTER () {
  local text=$1
  local zeilenbreite=$2
  local space=$(((zeilenbreite+${#text})/2))
  printf "%${space}s\n" "$text"
}

# Bei Abbruch des Programmes mit [CTRL+C], Terminal schließen, Kill-Befehl
trap 'FIN 1' 1 2 15


################################################################################
# Verbindungsaufbau
################################################################################
FN_VBA() {
  CHECKSCREEN 1

  { FLINE 2 "*" 80 1;echo "Herstellen der Verbindung zu $scuname";FLINE 0 "*" 80 2
    echo "eb-info:"; FLINE 0 "-" 8 1
  } >> $sculog

  {
    typeset -i gauge=0
    echo $gauge
    PINGCHECK
    if [ $? -eq $D_OK ];then
      gauge+=50
      echo $gauge
      sleep 0.3
      eb-info $scutcp > $tmpfile 2>$errlog
      if [ $? -eq $D_OK ];then
        tr -d '\000' < $tmpfile >> $sculog
        gauge+=50
        echo $gauge
        sleep 0.3
      else
        printf "\nFehler bei Aufruf: eb-info %s\n" "$scutcp" >> $errlog
        return 1
      fi
    else return 1;
    fi
  } >  >($DIAL "$BT" \
    --title " Verbindungsaufbau" \
    --gauge "" 0 0)

  dialog --clear
}

################################################################################
# Visueller LED-Test
################################################################################
FN_LED () {
  CHECKSCREEN 1
  typeset -i local badledcount=0
  local wtitle="Visueller Test aller LEDs"
  { FLINE 2 "*" 80 1;echo "$wtitle";FLINE 0 "*" 80 2; } >> $sculog;

  local LEDNAME=("SEL" "PU" "I8" "I7" "I6" "I5" "I4" "I3" "I2" "I1" "TRM" \
  "RCV" "12V" "INL" "DRQ" "DRY")

  local wincols=64;# Fensterbreite
  local retval=100
  while [ $retval -gt $D_OK ];do
    if [ $retval -eq $D_CANCEL ];then FIN 1
  elif [ $retval -eq $D_HELP ];then HLP "FN_LED" "$wtitle";fi
    $DIAL "$BT" --visit-items --scrollbar --separator " | " --separate-output --help-button --begin 2 $((($(tput cols)-wincols)/2)) \
    --title " Visuelle LED-Kontrolle - Blinken beim Einschalten der SIO3?"\
    --buildlist \
    "\n LEDs OK                        LEDs DEFEKT" 0 $wincols 0 \
    "0" ${LEDNAME[0]} "off"  "1" ${LEDNAME[1]} "off"  "2" ${LEDNAME[2]} "off" \
    "3" ${LEDNAME[3]} "off"  "4" ${LEDNAME[4]} "off"  "5" ${LEDNAME[5]} "off" \
    "6" ${LEDNAME[6]} "off"  "7" ${LEDNAME[7]} "off"  "8" ${LEDNAME[8]} "off" \
    "9" ${LEDNAME[9]} "off"  "10" ${LEDNAME[10]} "off"  "11" ${LEDNAME[11]} "off" \
    "12" ${LEDNAME[12]} "off"  "13" ${LEDNAME[13]} "off"  "14" ${LEDNAME[14]} "off" \
    "15" ${LEDNAME[15]} "off" 2>$tmpfile
    retval=$?
  done

  {
    printf "%-40s %s\n" "LEDs in Ordnung" "LEDs defekt"
    printf "%-40s %s\n" "---------------" "-----------"

    for ((i=0;i<16;i++));do
      local badled=$(grep -w "$i" $tmpfile)
      if [[ -n "$badled" ]];then
        printf "%-40s %s\n" " " "${LEDNAME[$i]}"
        badledcount=$badledcount+1
    else echo -e "${LEDNAME[$i]}";fi
    done
  } >> $sculog;

  { printf "%-60s %s\n" "$wtitle" "$badledcount"; } >> $summary
}

################################################################################
# Slaveadressen berechnen
################################################################################
FN_SLADR () {
  local uub="Slot-Adressen der Slaves:"
  { FLINE 2 "*" 80 1;echo "Ermittlung wichtiger Adressen";FLINE 0 "*" 80 2
    echo $uub;FLINE 0 "-" ${#uub} 0
  } >> $sculog;

  scuslave_baseadr=$(eb-find $scutcp $scu_vendor_id $scu_bus_master_dev_id 2>> $errlog)
  if [ $? -gt 0 ];then ERRMESSAGE "Slaveadressen berechnen";fi

  { echo -e " " > $tmpfile
    printf "Baseadr. = %s\n" "${scuslave_baseadr}"
    for ((i=1;i<=12;i++)) do
      local calculatedslotadr="$((10#$((scuslave_baseadr+0x20000*i+CID_GR_ADR)) ))";
      slaveadresse[$i]="0x$( printf "%X\n" $calculatedslotadr )"
      printf "Slot  "
      if [ $i -lt 10 ];then printf " ";fi
      printf "%s = %s\n" "$i" "${slaveadresse[$i]}"
    done
  } >> $tmpfile

  CHECKSCREEN 1
  $DIAL "$BT" \
  --title "SCU:     Berechnung der Slot-Adressen " \
  --exit-label "Weiter" \
  --textbox $tmpfile 0 0

  cat $tmpfile >> $sculog
}


################################################################################
# Scanne Slave Bus
################################################################################
FN_SLBUS () {
  { FLINE 2 "*" 80 1; echo "Scanne Slaves über CID Group der Slavebuskarten"
  FLINE 0 "*" 80 2; } >> $sculog;
  >$tmpfile
  CHECKSCREEN 1
  { for ((i=1,gauge=0;i<=12;i++,gauge+=10));do
      lesewert=$(eb-read $scutcp ${slaveadresse[i]}/2 2>> $errlog)
      if [ $? -eq 0 ];then
        { printf "Slavebuskarte in Slot: "
          if [ $i -lt 10 ];then printf " ";fi
          printf "%s gefunden" "$i"
          if [ 0x$lesewert == ${REG_VAL} ];then
            printf " -> SIO3\n"
            echo -e "Slot_$i SIO3 on" >> $tmpfile
          else
            printf " -> ?\n"
            echo -e "Slot_$i ? off" >> $tmpfile
          fi
        }>>$sculog
      fi
      echo $gauge
  done } > >(
  $DIAL "$BT" \
  --title " Scanne Slave-Bus" \
  --gauge "" 0 0)
  dialog --clear
}

################################################################################
# Slave Slot auswaehlen
################################################################################
FN_SLOT () {
  CHECKSCREEN 1

  local erfolg=$(wc -l < $tmpfile)
  if [ $erfolg -eq 0 ];then
    local ubcol="\Z1\Zb";local ub="Keine Slaves gefunden!! Manuell waehlen:"
    echo -e "$ub" >> $sculog
    for ((i=1;i<=12;i++));do option+=("Slot_$i" "?" "off");done
    local zeilen=12
  else
    local ubcol="\Z0\Zb";local ub="Slave Slot auswaehlen:"
    local option=($(cat $tmpfile))
    if [ $erfolg -lt 12 ];then
      option+=("Alternativwahl" "Slot_1-12" "off");
    typeset -i zeilen=$erfolg+1;fi
  fi

  local slotwahl=""
  while [ "$slotwahl" = "" ];do
    slotwahl=$($DIAL "$BT" --radiolist "$ubcol$ub" 0 0 $zeilen "${option[@]}" 3>&1 1>&2 2>&3)
    if [ $? -eq $D_CANCEL ]; then FIN 1;fi;#Pruefe Abbrechen-Button
    dialog --clear
  done

  # nochmalige Pruefung fuer Alternativwahl
  if [ $slotwahl == "Alternativwahl" ]; then
    unset option
    for ((i=1;i<=12;i++));do option+=("Slot_$i" "?" "off");done
    zeilen=12
    slotwahl=""
    while [ "$slotwahl" = "" ];do
      slotwahl=$($DIAL "$BT" --radiolist "$ubcol$ub" 0 0 $zeilen "${option[@]}" 3>&1 1>&2 2>&3)
      if [ $? -eq $D_CANCEL ]; then FIN 1;fi;#Pruefe Abbrechen-Button
      dialog --clear
    done
  fi

  echo -e "\n>>>>>| $slotwahl gewählt! |<<<<<" >> $sculog

  slotnr=${slotwahl##*_};# kuerze "Slot_xxx" auf "xxx"
  local calctestslave=$((scuslave_baseadr+0x20000*slotnr))
  testslaveadr=0x$( printf "%X\n" $calctestslave); #TESTSLAVE!!!
}


################################################################################
# Teste Standardregister
################################################################################
FN_SRS() {
  echo "0" > $countfile; #Fehlercounter fur Summary
  SRSADR=("Sl.Adr" 0x0001 0x0002 0x0003 0x0004 0x0005 0x0006 0x0007 \
  0x0008 0x0009 0x0010 0x0011)
  SRSADR32=("32 Bit" 0x0002 0x0004 0x0006 0x0008 0x000A 0x000C 0x000E \
  0x0010 0x0012 0x0020 0x0022)

  SRSNAME=("VHDL Variable" "Slave_ID" "FW_Version" "FW_Release" "CID_System" "CID_Group" \
    "VR_SCUBSL_Macro" "Ext._CID_System" "Ext._CID_Group" "CLK_10kHz" \
  "Echo_Register" "Status_Register")

  SRSTYPE=("R/W" r r r r r r r r r rw r)
  SRSDEF=("Default" 0xxxxx 0xxxxx 0xxxxx 0x0037 0x0045 0x0502 0x0000 \
  0x0000 0x30D4 0xxxxx 0x0003)
  SRSRESULT=("Read   ")
  SRSMARK=("   ")

  max_adr=$(MAXLENENTRY SRSADR[@])
  max_adr32=$(MAXLENENTRY SRSADR32[@])
  max_name=$(MAXLENENTRY SRSNAME[@])
  max_type=$(MAXLENENTRY SRSTYPE[@])
  max_def=$(MAXLENENTRY SRSDEF[@])
  max_result=$(MAXLENENTRY SRSRESULT[@])
  max_mark=$(MAXLENENTRY SRSMARK[@])
  typeset -i local wincols
  typeset -i local zeilen=${#SRSADR[*]};#Benoetigte Zeilen
  typeset -i local winlines=$zeilen+7

  # Funktion zum Lesen/Schreiben und Formatieren der Tabellenzeilen
  TABSRS() {
    local i=$1
    local rw=${SRSTYPE[$i]}
    typeset -i local count=($(cat $countfile))
    if [ $rw == "w" ];then
      typeset -i local testreg=$testslaveadr+${SRSADR32[$i]}
      eb-write $scutcp $testreg/2 ${SRSDEF[$i]} 2>> $errlog
      SRSRESULT[$i]=$(printf "%s\n" "------")
    elif [ $rw == "r" ] || [ $rw == "rw" ];then
      typeset -i testreg=$testslaveadr+${SRSADR32[$i]}
      typeset -u local result=$(eb-read $scutcp $testreg/2 2>> $errlog)
      SRSRESULT[$i]=$(printf "0x%s\n" "$result")
      if  [[ "${SRSRESULT[$i]}" == "${SRSDEF[$i]}" ]];then SRSMARK[$i]+="<OK"
      elif [[ "${SRSDEF[$i]}" == "0xxxxx" ]];then SRSMARK[$i]+="---"
      else SRSMARK[$i]+="<F ";count+=1; echo $count > $countfile
      fi
    fi

    printf "| %-${max_adr}s | %-${max_adr32}s | %-${max_name}s\
    | %-${max_type}s | %-${max_def}s | %-${max_result}s %-${max_mark}s\
    |\n"\
    "${SRSADR[$i]}" "${SRSADR32[$i]}" "${SRSNAME[$i]}" \
    "${SRSTYPE[$i]}" "${SRSDEF[$i]}" "${SRSRESULT[$i]}"\
    "${SRSMARK[$i]}"
  }

  local textline=$(TABSRS 0);local wincols=${#textline}+$DIABORDER; #Ermittle dialog-Fensterbreite

  CHECKSCREEN 1
  local wtitle="Lese SCU Slave-Standard Register Set"
  { FLINE 2 "*" 80 1;echo "$wtitle";FLINE 0 "*" 80 1; } >> $sculog;

  {
    for ((i=0;i<zeilen;i++));do
    unset textline
    local textline=$(TABSRS $i)
    if [ $i == 0 ] || [ $i == 1 ];then printf "-";FLINE 0 "=" $((${#textline}-2)) 0;echo "-";fi
    echo -e "$textline"
    if [ $i == $((zeilen-1)) ];then printf "-";FLINE 0 "=" $((${#textline}-2)) 0;echo "-";fi
  done } | tee $tmpfile | tee -a $sculog | $DIAL "$BT" \
  --title "$wtitle" \
  --extra-button --extra-label "Abbrechen" --help-button\
  --begin 3 $((($(tput cols)-wincols)/2)) --programbox $winlines $wincols
  typeset -i local retval=$?
  # Pruefe Buttons
  while [ $retval -gt $D_OK ];do
    if [ $retval -eq $D_EXTRA ];then FIN 1
    elif [ $retval -eq $D_HELP ];then HLP "FN_SRS" "$wtitle"
      { $DIAL "$BT" \
        --title "$wtitle" --input-fd 0 --stdout \
        --extra-button --extra-label "Abbrechen" --help-button\
        --begin 3 $((($(tput cols)-wincols)/2)) --programbox $winlines $wincols
      } < $tmpfile
      retval=$?
    fi
  done
  { printf "%-60s %s\n" "$wtitle" "$(cat $countfile)"; } >> $summary
}

################################################################################
# Teste Echo Register (Benutzt Arrays und TABSRS von Standardregister)
################################################################################
FN_ECHO () {
  CHECKSCREEN 1
  echo "0" > $countfile; #Fehlercounter fur Summary
  local wtitle="Schreibe/Lese Echo-Register"
  { FLINE 2 "*" 80 1;echo "$wtitle";FLINE 0 "*" 80 1; } >> $sculog;
  local echo_pos=10; #Arraypos Echoregister
  SRSDEF[0]="Ref.Val"
  local textline=$(TABSRS 0)
  typeset -i local wincols=${#textline}+$DIABORDER; # dialog-Fensterbreite
  typeset -i local winlines=12
  for ((xi=0;xi<5;xi++));do
    unset textline
    local textline=$(TABSRS 0)
    if [ $xi == 0 ];then
      printf "-";FLINE 0 "=" $((${#textline}-2)) 0;echo "-"
      echo -e "$textline"
      printf "-";FLINE 0 "=" $((${#textline}-2)) 0;echo "-"
    fi

    if [ $xi == 1 ] || [ $xi == 3 ];then
      SRSTYPE[$echo_pos]="w"
      if [ $xi == 1 ];then SRSDEF[$echo_pos]=$PAT1;else SRSDEF[$echo_pos]=$PAT2;fi
      textline=$(TABSRS $echo_pos)
      echo -e "$textline"
    elif [ $xi == 2 ] || [ $xi == 4 ];then
      SRSTYPE[$echo_pos]="r"
      if [ $xi == 2 ];then SRSDEF[$echo_pos]=$PAT1;else SRSDEF[$echo_pos]=$PAT2;fi
      textline=$(TABSRS $echo_pos)
      echo -e "$textline"
    fi
    if [ $xi == 4 ];then printf "-";FLINE 0 "=" $((${#textline}-2)) 0;echo "-";fi
  done | tee $tmpfile | tee -a $sculog | $DIAL "$BT" \
  --title "$wtitle" \
  --extra-button --extra-label "Abbrechen" --help-button\
  --begin 3 $((($(tput cols)-wincols)/2)) --programbox $winlines $wincols
  typeset -i local retval=$?

  # Pruefe Buttons
  while [ $retval -gt $D_OK ];do
    if [ $retval -eq $D_EXTRA ];then FIN 1
    elif [ $retval -eq $D_HELP ];then HLP "FN_ECHO" "$wtitle"
      { $DIAL "$BT" \
        --title "$wtitle" \
        --extra-button --extra-label "Abbrechen" --help-button\
        --begin 3 $((($(tput cols)-wincols)/2)) --programbox $winlines $wincols
      } < $tmpfile
      retval=$?
    fi
  done
  { printf "%-60s %s\n" "$wtitle" "$(cat $countfile)"; } >> $summary
}

################################################################################
# OneWire ID
################################################################################
FN_OW () {
  echo "0" > $countfile; #Fehlercounter fur Summary
  local OWADR=("Sl.Adr" 0x0040 0x0041 0x0042 0x0043)
  local OWADR32=("32 Bit" 0x0080 0x0082 0x0084 0x0086)
  local OWNAME=("Description" "CRC Code+Serial#" "Serial#" "Serial#" "Family Code")
  local OWTYPE=("Type" EEPROM EEPROM EEPROM EEPROM)
  local OWBFIELD=("Bitfield" 63..48 47..32 16..31 15..0)
  local OWRESULT=("Read   ")
  local OWMARK=("   ")

  local max_adr=$(MAXLENENTRY OWADR[@])
  local max_adr32=$(MAXLENENTRY OWADR32[@])
  local max_name=$(MAXLENENTRY OWNAME[@])
  local max_type=$(MAXLENENTRY OWTYPE[@])
  local max_bfield=$(MAXLENENTRY OWBFIELD[@])
  local max_result=$(MAXLENENTRY OWRESULT[@])
  local max_mark=$(MAXLENENTRY SRSMARK[@])
  typeset -i local wincols
  typeset -i local zeilen=${#OWADR[*]};#Benoetigte Zeilen
  typeset -i local winlines=$zeilen+14

  >$tmp2file

  # Funktion zum Lesen/Schreiben und Formatieren der Tabellenzeilen
  TABOW () {
    local i=$1
    local type=${OWTYPE[$i]}
    typeset -i local count=$(cat $countfile)
    if [ $type != "Type" ];then
      typeset -i local testreg=$testslaveadr+${OWADR32[$i]}
      typeset -u local result=$(eb-read $scutcp $testreg/2 2>> $errlog)
      OWRESULT[$i]=$(printf "0x%s\n" "$result")
      printf "%s" "$result" >> $tmp2file;
      if [ $i == 4 ];then
        local famcode="$(grep -E -o ..$ < <(echo $result))"
        if [ $i == 4 -a $famcode == 43 ];then OWMARK[$i]="<OK";#kuerze result auf xx
        else OWMARK[$i]="<F ";count+=1; echo $count > $countfile;fi
      else OWMARK[$i]="---";fi
    fi

    printf "| %-${max_adr}s | %-${max_adr32}s | %-${max_name}s\
    | %-${max_type}s | %-${max_bfield}s | %-${max_result}s %-${max_mark}s |\n"\
    "${OWADR[$i]}" "${OWADR32[$i]}" "${OWNAME[$i]}"\
    "${OWTYPE[$i]}" "${OWBFIELD[$i]}" "${OWRESULT[$i]}" "${OWMARK[$i]}"
  }
  local textline=$(TABOW 0);wincols=${#textline}+$DIABORDER; #Ermittle dialog-Fensterbreite

  CHECKSCREEN 1
  local wtitle="OneWire ID auslesen"
  { FLINE 2 "*" 80 1;echo "$wtitle";FLINE 0 "*" 80 1; } >> $sculog;

  for ((i=0;i<zeilen;i++));do
    unset textline
    local textline=$(TABOW $i)
    if [ $i == 0 -o $i == 1 ];then printf "-";FLINE 0 "=" $((${#textline}-2)) 0;echo "-";fi
    if [ $i == 1 ];then echo "| EEPROM (DS28EC20)                                                       |";fi
    echo -e "$textline"
    if [ $i == $((zeilen-1)) ];then printf "-";FLINE 0 "=" $((${#textline}-2)) 0;echo "-"
      echo "SIO3;CID;$cid_id;One-Wire_U15;$(cat $tmp2file)" > $onwireidfile

      # CRC berechnen (Variabeln/Berechnungen werden in Integer durchgefuehrt)
      for ((z=0;z<56;z++));do

        if [ $z == 0 ]; then
          typeset -i local ID=$(printf "0x";cat $tmp2file)
          typeset -i local crcData=$(( $ID & 0x00FFFFFFFFFFFFFF ))
          typeset -i local crcReceived=$(( (( $ID & 0xFF00000000000000 ) >> 56 ) & 0x000000000000FF ))
          #typeset -i local crcData=$(printf "0x";echo "$ID" | grep -o -E ".{14}$")
          printf "\n%s 0x%X\n" "OneWire ID: " "$ID"
          printf "%s 0x%X\n" "OneWire CRC-Data: " "$crcData"
          typeset -i local databit=0x00
          typeset -i local CRC=0x00
          typeset -i local CRC_Temp=0x00
        fi

        dataBit=$(( $crcData & 0x01 << $z ))
        if [ $dataBit -gt 0 ];then CRC_Temp=$(( ($CRC & 0x01)^1 ))
        else CRC_Temp=$(( ($CRC & 0x01)^0 ));fi

        if [ $(( $CRC & 0x02 )) -gt 0 ];then CRC=$(( $CRC | 0x01 ))
        else CRC=$(( $CRC & ~0x01 ));fi

        if [ $(( $CRC & 0x04 )) -gt 0 ];then CRC=$(( $CRC | 0x02 ))
        else CRC=$(( $CRC & ~0x02 ));fi

        if [ $(( $CRC & 0x08 )) -gt 0 -a $(( $CRC_Temp^1 )) -gt 0 ] || [ $(( $CRC & 0x08 )) -eq 0 -a $(( $CRC_Temp^0 )) -gt 0 ];then CRC=$(( $CRC | 0x04 ))
        else CRC=$(( $CRC & ~0x04 ));fi

        if [ $(( $CRC & 0x10 )) -gt 0 -a $(( $CRC_Temp^1 )) -gt 0 ] || [ $(( $CRC & 0x10 )) -eq 0 -a $(( $CRC_Temp^0 )) -gt 0 ];then CRC=$(( $CRC | 0x08 ))
        else CRC=$(( $CRC & ~0x08 ));fi

        if [ $(( $CRC & 0x20 )) -gt 0 ];then CRC=$(( $CRC | 0x10 ))
        else CRC=$(( $CRC & ~0x10 ));fi

        if [ $(( $CRC & 0x40 )) -gt 0 ];then CRC=$(( $CRC | 0x20 ))
        else CRC=$(( $CRC & ~0x20 ));fi

        if [ $(( $CRC & 0x80 )) -gt 0 ];then CRC=$(( $CRC | 0x40 ))
        else CRC=$(( $CRC & ~0x40 ));fi

        if [ $CRC_Temp -gt 0 ];then CRC=$(( $CRC | 0x80 ))
        else CRC=$(( $CRC & ~0x80 ));fi
      done
      printf "\n%s 0x%X\n" "CRC-Pruefsumme (empfangen): " "$crcReceived"
      printf "%s 0x%X"   "CRC-Pruefsumme (berechnet): " "$CRC"

      if [ $crcReceived -eq $CRC ];then echo " <OK";
      else
        echo " <F"
        typeset -i local count=$(cat $countfile)
        count+=1
        echo $count > $countfile
      fi

    fi
  done | tee $tmpfile | tee -a $sculog | $DIAL "$BT" \
  --title "$wtitle" \
  --extra-button --extra-label "Abbrechen" --help-button\
  --begin 3 $((($(tput cols)-wincols)/2)) --programbox $winlines $wincols
  typeset -i local retval=$?
  # Pruefe Buttons
  while [ $retval -gt $D_OK ];do
    if [ $retval -eq $D_EXTRA ];then FIN 1
    elif [ $retval -eq $D_HELP ];then HLP "FN_OW" "$wtitle"
      { $DIAL "$BT" \
        --title "$wtitle" \
        --extra-button --extra-label "Abbrechen" --help-button\
        --begin 3 $((($(tput cols)-wincols)/2)) --programbox $winlines $wincols
      } < $tmpfile
      retval=$?
    fi
  done
  { printf "%-60s %s\n" "$wtitle" "$(cat $countfile)"; } >> $summary
}

################################################################################
# Device-Bus-Interlock-Test
################################################################################
FN_DB_INT () {

  SHOW_DEV () {
    $DIAL "$BT" \
    --title "Device-Bus Interrupt: Signal- und LED Test [ 1/2 ]" \
    --mixedgauge "Stecken Sie den Test-Adapter auf die Device Bus Buchse und betaetigen Sie die drei Taster für (INL), (DRQ) und (DRY).\nBeobachten Sie die zugehoerige LED, waehrend ein Taster gedrueckt ist.\n\nWenn ein Signal nicht erkannt wird, druecken Sie die Taste \"W\" zum Fortfahren." \
    0 0 $1 \
    "Interlock active    (INL)"	"$2" \
    "Data request active (DRQ)"	"$3" \
    "Data ready active   (DRY)"	"$4"
  }

  local inl="warten..."
  local drq="warten..."
  local dry="warten..."
  typeset -i local inlfl=0
  typeset -i local drqfl=0
  typeset -i local dryfl=0

  SHOW_DEV 0 $inl $drq $dry

  typeset -i local i=0
  while [ $inlfl -eq 0 -o $drqfl -eq 0 -o $dryfl -eq 0 ];do

    typeset -i local testreg=$testslaveadr+0x0040
    typeset -u local result=$(eb-read $scutcp $testreg/2 2>> $errlog)

    case "$result" in
      0010) if [ $drqfl -eq 0 ];then
      drq="erkannt";i+=33;SHOW_DEV $i $inl $drq $dry;drqfl=1;fi ;;
      0020) if [ $dryfl -eq 0 ];then
      dry="erkannt";i+=33;SHOW_DEV $i $inl $drq $dry;dryfl=1;fi ;;
      0040) if [ $inlfl -eq 0 ];then
      inl="erkannt";i+=33;SHOW_DEV $i $inl $drq $dry;inlfl=1;fi ;;
    esac
    read -s -n 1 -t 0.05 key
    if [ "$key" == "W" -o "$key" == "w" ];then
      $DIAL "$BT" \
      --title " Interrupttest vorzeitig abbrechen?" \
      --yesno "\nEs wurden noch nicht alle Signale bestaetigt.\nMoechten Sie trotzdem fortfahren?" 0 0
      typeset -i retval=$?
      if [ $retval -eq $D_OK ];then break
    else SHOW_DEV $i $inl $drq $dry;fi
    fi
  done
  typeset -i local count=0
  if [ $inlfl -eq 1 -a $drqfl -eq 1 -a $dryfl -eq 1 ];then sleep 1;fi
  if [ $inl == "warten..." ];then inl="nicht bestaetigt!";count+=1;fi
  if [ $drq == "warten..." ];then drq="nicht bestaetigt!";count+=1;fi
  if [ $dry == "warten..." ];then dry="nicht bestaetigt!";count+=1;fi
  local wtitle="Device-Bus [Test-Adapter]:"
  local uub="Signal-Test"
  { printf "%-60s %s\n" "$wtitle $uub" "$count"; } >> $summary

  { FLINE 2 "*" 80 1;echo "$wtitle";FLINE 0 "*" 80 2;
    echo $uub;FLINE 0 "-" ${#uub} 1
    echo -e "Interlock active    (INL)\t$inl"
    echo -e "Data request active (DRQ)\t$drq"
    echo -e "Data ready active   (DRY)\t$dry"
  } >> $sculog;

  # LED-Test
  CHECKSCREEN 1
  local uub="Visuelle LED-Kontrolle bei Tastendruck (INL,DRQ,DRY) [2/2]"
  { echo -e "\n\n$uub";FLINE 0 "-" ${#uub} 1; } >> $sculog;

  local LEDNAME=("INL" "DRQ" "DRY")

  local wincols=64;# Fensterbreite
  local retval=100
  while [ $retval -gt $D_OK ];do
    if [ $retval -eq $D_CANCEL ];then FIN 1
  elif [ $retval -eq $D_HELP ];then HLP "FN_DB_INT" "$uub";fi
    $DIAL "$BT" --visit-items --scrollbar --separator " | " --separate-output --help-button --begin 2 $((($(tput cols)-wincols)/2)) \
    --title " $uub"\
    --buildlist \
    "\n LEDs OK                        LEDs DEFEKT" 0 $wincols 0 \
    "0" ${LEDNAME[0]} "off"  "1" ${LEDNAME[1]} "off"  "2" ${LEDNAME[2]} "off" 2>$tmpfile
    retval=$?
  done

  {
    printf "%-40s %s\n" "LEDs in Ordnung" "LEDs defekt"
    printf "%-40s %s\n" "---------------" "-----------"
    count=0
    for ((i=0;i<3;i++));do
      local badled=$(grep -w "$i" $tmpfile)
      if [[ -n "$badled" ]];then printf "%-40s %s\n" " " "${LEDNAME[$i]}";count+=1;
    else echo -e "${LEDNAME[$i]}";fi
    done
  } >> $sculog;
  { printf "%-60s %s\n" "$wtitle LED-Kontrolle" "$count"; } >> $summary
}


################################################################################
# Device-Bus-IFK-Test (Echo Register)
################################################################################
FN_DB_IFK () {
  CHECKSCREEN 1
  echo "0" > $countfile; #Fehlercounter fur Summary
  $DIAL "$BT" \
  --title " Verbindung zur IFK herstellen (Device Bus) " \
  --yes-label "Weiter" \
  --no-label "Abbrechen" \
  --yesno "\nVerbinden Sie die SIO3 ueber den Device-Bus mit der IFK und schalten Sie das System ein.\n\nDie Adresse der IFK muss auf 0x79 stehen." 0 0
  typeset -i local retval=$?
  if [ $retval -eq $D_CANCEL ];then FIN 1;fi

  readonly local sc="MIL Ctrl/Status"
  readonly local rst="Reset"
  readonly local cb="Data Command Bus"
  readonly local db="Data Device Bus"
  readonly local sa="Status available"
  readonly local se="Status error"


  local MILADR=("Sl.Adr"           0x402  " "  0x412  0x412  0x000   " "  0x401  0x401  0xC01  " "  0x000   0x000   0xD01  )
  local MILADR32=("32Bit"          0x804  " "  0x824  0x824  0x1C00  " "  0x800  0x802  0x1802 " "  0x1C00  0x1C20  0x1A02 )
  local MILNAME=("Description IFK" "$sc"  " "  "$rst" "$rst" "$sa"   " "  "$cb"  "$db"  "$db"  " "  "$sa"   "$se"   "$db"  )
  local MILIFKCODE=("Code"         ""     " "  ""     ""     ""      " "  ""     0x13   0x89   " "  ""      ""      ""     )
  local MILIFKADR=("Adr"           ""     " "  ""     ""     ""      " "  ""     0x79   0x79   " "  ""      ""      ""     )
  local MILTYPE=("R/W"             rw     -    w      w      r       -    w      w      w      -    r       r       r      )
  local MILWRITE=("Write "         0x9000 " "  0x0000 0xFFFF 0x0000  " "  0xA5A5 0x1379 0x8979 " "  0x0002  0x0000  0xA5A5 )
  local MILREAD=("Read  ")
  local MILMARK=("   ")

  local max_adr=$(MAXLENENTRY MILADR[@])
  local max_adr32=$(MAXLENENTRY MILADR32[@])
  local max_name=$(MAXLENENTRY MILNAME[@])
  local max_ifkcode=$(MAXLENENTRY MILIFKCODE[@])
  local max_ifkadr=$(MAXLENENTRY MILIFKADR[@])
  local max_read=$(MAXLENENTRY MILREAD[@])
  local max_write=$(MAXLENENTRY MILWRITE[@])
  local max_mark=$(MAXLENENTRY MILMARK[@])

  typeset -i local wincols
  typeset -i local zeilen=${#MILADR[*]};#Benoetigte Zeilen
  typeset -i local winlines=$zeilen+7

  # Funktion zum Lesen/Schreiben und Formatieren der Tabellenzeilen
  TABMIL() {
    local i=$1
    local rw=${MILTYPE[$i]}
    typeset -i local count=($(cat $countfile))
    if [ $rw == "w" ];then
      typeset -i local testreg=$testslaveadr+${MILADR32[$i]}
      eb-write $scutcp $testreg/2 ${MILWRITE[$i]} 2>> $errlog
    elif [ $rw == "r" ];then
      typeset -i local testreg=$testslaveadr+${MILADR32[$i]}
      typeset -u local result=$(eb-read $scutcp $testreg/2 2>> $errlog)
      MILREAD[$i]=$(printf "0x%s\n" "$result")
      if  [[ "${MILREAD[$i]}" == "${MILWRITE[$i]}" ]];then MILMARK[$i]+="<OK"
      else MILMARK[$i]+="<F ";count+=1; echo $count > $countfile
      fi
      MILWRITE[$i]=""; #Loesche aus Anzeige
    elif [ $rw == "rw" ];then
      typeset -i local testreg=$testslaveadr+${MILADR32[$i]}
      eb-write $scutcp $testreg/2 ${MILWRITE[$i]} 2>> $errlog
      typeset -u local result=$(eb-read $scutcp $testreg/2 2>> $errlog)
      MILREAD[$i]=$(printf "0x%s\n" "$result")
    fi

    printf "| %-${max_adr}s | %-${max_adr32}s | %-${max_name}s | %-${max_ifkcode}s | %-${max_ifkadr}s | %-${max_write}s | %-${max_read}s %-${max_mark}s |\n"\
    "${MILADR[$i]}" "${MILADR32[$i]}" "${MILNAME[$i]}" "${MILIFKCODE[$i]}" "${MILIFKADR[$i]}" "${MILWRITE[$i]}" "${MILREAD[$i]}" "${MILMARK[$i]}"
  }

  local textline=$(TABMIL 0);wincols=${#textline}+$DIABORDER; #Ermittle dialog-Fensterbreite

  CHECKSCREEN 1
  local wtitle="Device Bus [IFK]: Schreibe/Lese Echo-Register"
  { FLINE 2 "*" 80 1;echo "$wtitle";FLINE 0 "*" 80 1; } >> $sculog;

  for ((i=0;i<zeilen;i++));do
    unset textline
    local textline=$(TABMIL $i)
    if [ $i == 0 -o $i == 1 ];then printf "-";FLINE 0 "=" $((${#textline}-2)) 0;echo "-";fi
    echo -e "$textline"
    if [ $i == $((zeilen-1)) ];then printf "-";FLINE 0 "=" $((${#textline}-2)) 0;echo "-";fi
  done | tee $tmpfile | tee -a $sculog | $DIAL "$BT" \
  --title "$wtitle" \
  --extra-button --extra-label "Abbrechen" --help-button\
  --begin 3 $((($(tput cols)-wincols)/2)) --programbox $winlines $wincols
  typeset -i local retval=$?
  # Pruefe Buttons
  while [ $retval -gt $D_OK ];do
    if [ $retval -eq $D_EXTRA ];then FIN 1
    elif [ $retval -eq $D_HELP ];then HLP "FN_DB_IFK" "$wtitle"
      { $DIAL "$BT" \
        --title "$wtitle" \
        --extra-button --extra-label "Abbrechen" --help-button\
        --begin 3 $((($(tput cols)-wincols)/2)) --programbox $winlines $wincols
      } < $tmpfile
      retval=$?
    fi
  done
  { printf "%-60s %s\n" "$wtitle" "$(cat $countfile)"; } >> $summary
}


################################################################################
# main
################################################################################
{ CENTER "----------------------" 80
  CENTER "| SIO3 Funktionstest |" 80
  CENTER "----------------------" 80
  FLINE 0 ">" 80 1
  echo -e "SCU-Name:\t\t $scuname"
  echo -e "SIO3-CID:\t\t $cid_id "
  echo -e "Geprueft von:\t\t $lastname"
  echo -e "Geprueft am:\t\t $date"
  FLINE 0 "<" 80 1
} >> $sculog

{ FLINE 0 "*" 80 1
  echo -e "ZUSAMMENFASSUNG"
  FLINE 0 "*" 80 2
  printf "%-60s %s\n" "Testabschnitt" "Fehleranzahl"
  FLINE 0 "-" 80 1
} >> $summary


#Scriptablauf
while [ 1 ];do
  FN_VBA
  if [ $? -ne $D_OK ];then ERRMESSAGE "Verbindungsaufbau";else break;fi
done

FN_LED
FN_SLADR
#slotnr=6
#scuslave_baseadr=$(eb-find $scutcp $scu_vendor_id $scu_bus_master_dev_id 2>> $errlog)
#typeset -i calctestslave=$((scuslave_baseadr+0x20000*slotnr))
#testslaveadr=0x$( printf "%X\n" $calctestslave ); #TESTSLAVE!!!
FN_SLBUS
FN_SLOT
FN_SRS
FN_ECHO
FN_OW
FN_DB_INT
FN_DB_IFK

FIN 0
