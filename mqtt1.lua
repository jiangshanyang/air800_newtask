
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
local count_gps=0 --GPS累计多少次延迟没有发送
local count_bat=0 --电池数据累计多少次延迟没有发送

--- MQTT连接是否处于激活状态
-- @return 激活状态返回true，非激活状态返回false
-- @usage mqttTask.isReady()
--[[
function isReady()
	log.info("jsy isReady")
    return ready
end]]



--ntp.timeSync(8)  --8小时同步一次时钟
--sys.timerLoopStart(sys.restart('每24小时软件重启，every 24 hours to software reboot',86400000))

function f_mqtt()
        while true do
			--等待网络环境准备就绪
			while not socket.isReady() do sys.waitUntil("IP_READY_IND") end
			local imei = misc.getImei()
			--创建一个MQTT客户端
			local mqttClient = mqtt.client(DEVC_ID,300,PROD_ID,PASSWD)
			--阻塞执行MQTT CONNECT动作，直至成功
			--如果使用ssl连接，打开--[[,{caCert="ca.crt"}]]，根据自己的需求配置
			while not mqttClient:connect(ADDR,PORT,PROT--[[,{caCert="ca.crt"}]]) do
				sys.wait(1000)
			end
			uart1.write_cmd('p0.cmd.txt="connect ok"')
            while true do
            	local buf1=gps1.packGPS()
				local label=0  --标志是否有定位数据,0没有定位数据，1，有一个定位数据，2：有二个定位数据
				if gps1.Mlat~=nil and  lat_tmp1~=""  then
					label=2
					lon_tmp=math.ceil(math.abs(tonumber(lon_tmp1)-tonumber(gps1.Mlng))*100000)  ---计算大概多少米的距离   
					lat_tmp=math.ceil(math.abs(tonumber(lat_tmp1)-tonumber(gps1.Mlat))*100000)
				end
				if gps1.Mlat~=nil and lat_tmp1=="" then
					label=1
				end
				--GPS定位如果变化不超过20米，LBS定位变化不超过100米，不重新发定位信息到服务器上,lon_tmp1是前面的数据,Mlng是当前的数据
				log.info("label,count_gps",tostring(label),tostring(count_gps))
				log.info("lon_tmp1,Mlng,lat_tmp1,Mlat,tostring(lon_tmp),tostring(lat_tmp):",lon_tmp1,gps1.Mlng,lat_tmp1,gps1.Mlat,tostring(lon_tmp),tostring(lat_tmp))
            	if label==1 or (label==2 and buf1 ~= "" and (
					(string.len(gps1.Mlat)==10 and (lon_tmp+lat_tmp)>50 and (lon_tmp+lat_tmp)<2000 )   --GPS定位改变的距离
					or (string.len(gps1.Mlat)==11 and (lon_tmp+lat_tmp)>200 and (lon_tmp+lat_tmp)<10000 )  --LBS定位改变的距离
					or count_gps>360  --连续1个小时位置不变，也发送一次定位数据
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
					-- 异常情况或高温超过60度或电流大于50，每10秒钟发一次，正常情况电流1-50之间，每一分钟发一次，正常情况且电流小于1,5分钟发一次电池数据
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
            --断开MQTT连接
            mqttClient:disconnect()
        end 
    end
--启动MQTT客户端任务
sys.taskInit(f_mqtt)
