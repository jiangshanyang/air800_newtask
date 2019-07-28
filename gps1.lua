
module(...,package.seeall)

require"gps"
require"agps"
require"lbsLoc"
require"common"

local Rlat = ""
local Rlng = ""
--[[
����  �����Ͳ�ѯλ������
����  ����
����ֵ����
]]
local function reqLbsLoc()
    reqAddr = not reqAddr
    lbsLoc.request(getLocCb,reqAddr)
end

--[[
����  ����ȡ��վ��Ӧ�ľ�γ�Ⱥ�Ļص�����
����  ��
		result��number���ͣ�0��ʾ�ɹ���1��ʾ���绷����δ������2��ʾ���ӷ�����ʧ�ܣ�3��ʾ��������ʧ�ܣ�4��ʾ���շ�����Ӧ��ʱ��5��ʾ���������ز�ѯʧ�ܣ�Ϊ0ʱ�������3��������������
		lat��string���ͣ�γ�ȣ���������3λ��С������7λ������031.2425864
		lng��string���ͣ����ȣ���������3λ��С������7λ������121.4736522
		addr��string���ͣ�UCS2��˱����λ���ַ���������lbsLoc.requestʱ����ĵڶ�������Ϊtrueʱ���ŷ��ر�����
����ֵ����
]]
function getLocCb(result,lat,lng,addr)
    --log.info("testLbsLoc.getLocCb",result,lat,lng,result==0 and common.ucs2beToGb2312(addr) or "")
    --��ȡ��γ�ȳɹ�
    if result==0 then
    	Rlat = lat
    	Rlng = lng
    	log.info("testLbsLoc success",Rlat,Rlng)
    else
    	Rlat = ""
    	Rlng = ""
    end
    
end


function getGPS()
    if gps.isFix() then
    	local tLocation = gps.getLocation()
		uart1.write_cmd('p0.cmd.txt="air GPS OK."')
    	Rlat = tLocation.lat
    	Rlng = tLocation.lng
		g_bat["satenum"]=gps.getUsedSateCnt()
		--g_bat["speed"]=
	    --log.info("getGPS success,jiangshanyang",gps.isOpen(),gps.isFix(),tLocation.lngType,tLocation.lng,tLocation.latType,tLocation.lat,gps.getAltitude(),gps.getSpeed(),gps.getCourse(),gps.getViewedSateCnt(),gps.getUsedSateCnt())
		log.info("getGPS success","jiangshanyang")
    else
    	log.info("get GPS fail!","get LBS")
		uart1.write_cmd('p0.cmd.txt="air GPS fail! get LBS"')
		reqLbsLoc()
    end
    if Rlat~=nil and Rlng~=nil then
		g_bat["long"]=Rlng
		g_bat["lati"]=Rlat   		
		g_bat["gpsnew"]=true
		g_bat["gpsok"]=true	

	end
	return Rlat,Rlng

end

local function test1Cb(tag)
    log.info("testGps.test1Cb",tag)
    --getGPS()
end


--����GPS+BD��λ
--��������ô˽ӿڣ�Ĭ��ҲΪGPS+BD��λ
--gps.setAerialMode(1,1,0,0)

--���ý�gps.lua�ڲ�����NEMA����
--��������ô˽ӿڣ�Ĭ��ҲΪ��gps.lua�ڲ�����NEMA����
--���gps.lua�ڲ���������NMEA����ͨ���ص�����cb�ṩ���ⲿ��������������Ϊ1,nmeaCb
--���gps.lua���ⲿ���򶼴�����������Ϊ2,nmeaCb
-- gps.setNmeaMode(2,nmeaCb)

-- test(testIdx)
gps.open(gps.DEFAULT,{tag="TEST1",cb=test1Cb})
--sys.timerLoopStart(getGPS,20000)

function packGPS()
    Mlat,Mlng = getGPS()
	if Mlat==nil or Mlng==nil or Mlat=="" or Mlng=="" then
		log.info("gps1 ","lat and lng nil")
		return ""
	end
    log.info("gps1 lat,lng",Mlat,Mlng)
	uart1.write_cmd('p0.long.txt="'.. g_bat["long"] ..'"')
	uart1.write_cmd('p0.lati.txt="'.. g_bat["lati"] ..'"')
	local t = misc.getClock() 	--{year=2017,month=2,day=14,hour=14,min=19,sec=23}
	local tt=t.year..'-'..t.month..'-'..t.day..' '.. t.hour ..':'.. string.format("%02d",t.min) ..':'.. string.format("%02d",t.sec)
	uart1.write_cmd('main.tim.txt="'.. tt ..'"')
	local speed1,speed2=gps.getSpeed()
    local torigin = 
      {
        datastreams = 
        {{
          id = "gps_info",
          datapoints = 
          {{
            at = "",
            value = 
            {
              lon = Mlng,
              lat = Mlat,
			  tim = tt,
			  rssi = net.getRssi(),
			  satenum = g_bat["satenum"],
			  speed1=speed1,
			  speed2=speed2
            }
          }}
        }}
      }

    local msg = json.encode(torigin)
    print("json data",msg)
    local len = msg.len(msg)
    local buf = pack.pack("bbbA", 0x01,0x00,len,msg)
    return buf
end

sys.taskInit(
	function()
		while true do
			uart1.write_cmd('main.gps_st.txt=" ' .. g_bat["satenum"] .. ' "')
			uart1.write_cmd('main.gprs_st.txt=" ' .. net.getRssi() .. ' "')
			sys.wait(30000)
		end
	end
)