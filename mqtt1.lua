
module(...,package.seeall)

require"misc"
require"mqtt"
require"ntp"
ntp.timeSync()
require"gps1"
require"uart1"

local ready = false
local lon_tmp1=""
local lat_tmp1=""
local lon_tmp,lat_tmp
local count_gps=0 --GPS�ۼƶ��ٴ��ӳ�û�з���
local count_bat=0 --��������ۼƶ��ٴ��ӳ�û�з���

--- MQTT�����Ƿ��ڼ���״̬
-- @return ����״̬����true���Ǽ���״̬����false
-- @usage mqttTask.isReady()
--[[
function isReady()
	log.info("jsy isReady")
    return ready
end]]



--ntp.timeSync(8)  --8Сʱͬ��һ��ʱ��
--sys.timerLoopStart(sys.restart('ÿ24Сʱ���������every 24 hours to software reboot',86400000))

function f_mqtt()
        while true do
			--�ȴ����绷��׼������
			while not socket.isReady() do sys.waitUntil("IP_READY_IND") end
			local imei = misc.getImei()
			--����һ��MQTT�ͻ���
			local mqttClient = mqtt.client(DEVC_ID,300,PROD_ID,PASSWD)
			--����ִ��MQTT CONNECT������ֱ���ɹ�
			--���ʹ��ssl���ӣ���--[[,{caCert="ca.crt"}]]�������Լ�����������
			while not mqttClient:connect(ADDR,PORT,PROT--[[,{caCert="ca.crt"}]]) do
				sys.wait(1000)
			end
			uart1.write_cmd('p0.cmd.txt="connect ok"')
            while true do
            	local buf1=gps1.packGPS()
				local label=0  --��־�Ƿ��ж�λ����,0û�ж�λ���ݣ�1����һ����λ���ݣ�2���ж�����λ����
				if gps1.Mlat~=nil and  lat_tmp1~=""  then
					label=2
					lon_tmp=math.ceil(math.abs(tonumber(lon_tmp1)-tonumber(gps1.Mlng))*100000)  ---�����Ŷ����׵ľ���   
					lat_tmp=math.ceil(math.abs(tonumber(lat_tmp1)-tonumber(gps1.Mlat))*100000)
				end
				if gps1.Mlat~=nil and lat_tmp1=="" then
					label=1
				end
				--GPS��λ����仯������20�ף�LBS��λ�仯������100�ף������·���λ��Ϣ����������,lon_tmp1��ǰ�������,Mlng�ǵ�ǰ������
				log.info("label,count_gps",tostring(label),tostring(count_gps))
				log.info("lon_tmp1,Mlng,lat_tmp1,Mlat,tostring(lon_tmp),tostring(lat_tmp):",lon_tmp1,gps1.Mlng,lat_tmp1,gps1.Mlat,tostring(lon_tmp),tostring(lat_tmp))
            	if label==1 or (label==2 and buf1 ~= "" and (
					(string.len(gps1.Mlat)==10 and (lon_tmp+lat_tmp)>50 and (lon_tmp+lat_tmp)<2000 )   --GPS��λ�ı�ľ���
					or (string.len(gps1.Mlat)==11 and (lon_tmp+lat_tmp)>200 and (lon_tmp+lat_tmp)<10000 )  --LBS��λ�ı�ľ���
					or count_gps>360  --����1��Сʱλ�ò��䣬Ҳ����һ�ζ�λ����
					)) then  
				    log.info("gps/lbs send to onenet!",lon_tmp1,gps1.Mlng,lat_tmp1,gps1.Mlat,tostring(lon_tmp),tostring(lat_tmp))
					result = mqttClient:publish("$dp",buf1)
					if label==1 or result then 
						lon_tmp1=gps1.Mlng
						lat_tmp1=gps1.Mlat
					end
					if result then
						log.info("gps onenet send","success")
						uart1.write_cmd('p0.cmd.txt="send gps ok!"')
						count_gps=1
					else
						log.info("gps onenet send","failed")
						uart1.write_cmd('p0.cmd.txt="gps onenet send failed"')
						mqttClient:disconnect()
						while not socket.isReady() do 
							sys.waitUntil("IP_READY_IND") 
							log.info("jiangshanyang","mqtt_gps1")
						end
						mqttClient = mqtt.client(DEVC_ID,300,PROD_ID,PASSWD)
						while not mqttClient:connect(ADDR,PORT,PROT--[[,{caCert="ca.crt"}]]) do
							sys.wait(2000)
							log.info("jiangshanyang","mqtt_gps2")
						end
						log.info("jiangshanyang","mqtt_gps3")
						mqttClient:publish("$dp",buf1)
					end
				else
				    log.info("not send to onenet!",lon_tmp1,gps1.Mlng,lat_tmp1,gps1.Mlat,tostring(lon_tmp),tostring(lat_tmp))
					if label>0 then count_gps=count_gps+1 end
				end 

            	local buf2=uart1.packBAT()
				if buf2~="" then
					local I_tmp=g_bat["I_total"]/10
					log.info("Bat buf2",buf2)
					log.info("count_bat",tostring(count_bat))
					-- �쳣�������³���60�Ȼ��������50��ÿ10���ӷ�һ�Σ������������1-50֮�䣬ÿһ���ӷ�һ�Σ���������ҵ���С��1,5���ӷ�һ�ε������
					--if g_bat["cntl_x"]~=208 or g_bat["warn_x"]~=0 or I_tmp>50 or g_bat["T_max"]>60 or (I_tmp>=1 and count_bat>6) or (I_tmp<1 and count_bat>360) then  
					if buf2~=""  then  
						log.info("BAT send to onenet!",buf2)
						result = mqttClient:publish("$dp",buf2)
						if result then
							log.info("BAT onenet send","success")
							uart1.write_cmd('p0.cmd.txt="send bat ok!"')
						else
							log.info("BAT onenet send","failed")
							uart1.write_cmd('p0.cmd.txt="BAT onenet send failed"')
							mqttClient:disconnect()
							while not socket.isReady() do 
								sys.waitUntil("IP_READY_IND") 
								log.info("jiangshanyang","mqtt_bat1")
							end
							mqttClient = mqtt.client(DEVC_ID,300,PROD_ID,PASSWD)
							while not mqttClient:connect(ADDR,PORT,PROT--[[,{caCert="ca.crt"}]]) do
								sys.wait(2000)
								log.info("jiangshanyang","mqtt_bat2")
							end
							log.info("jiangshanyang","mqtt_bat3")
							mqttClient:publish("$dp",buf2)
						end
						count_bat=0
					else 
						log.info("BAT not send to onenet!buf2=",buf2)
						count_bat=count_bat+1
					end 
				end
				uart1.write_cmd('p0.imei.txt="' .. imei ..'"')
				sys.wait(10000)
            end 
            --�Ͽ�MQTT����
            mqttClient:disconnect()
        end 
    end
--����MQTT�ͻ�������
sys.taskInit(f_mqtt)
