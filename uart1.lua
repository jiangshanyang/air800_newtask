

module(...,package.seeall)
require"utils"
require"pm"

--串口ID, 1对应uart1  
local UART_ID = 1
--串口读到的数据缓冲区
local rdbuf = ""

--air800常开
local air800_always_online = 1

--local OFFTIME = 10	--air不放电关机倒计时 单位0.5min
--local OFFCurrent = 20  --总电流单位0.1A  充放电单位0.01A    0.2A关机 0.3A不关机


--g_bat["using"] = OFFTIME	--电池开机第一次air800不关机时间，单位0.5分钟

function print_r ( t )  
    local print_r_cache={}
    local function sub_print_r(t,indent)
        if (print_r_cache[tostring(t)]) then
            log.info(indent.."*"..tostring(t))
        else
            print_r_cache[tostring(t)]=true
            if (type(t)=="table") then
                for pos,val in pairs(t) do
                    if (type(val)=="table") then
                        log.info(indent.."["..pos.."] => "..tostring(t).." {")
                        sub_print_r(val,indent..string.rep(" ",string.len(pos)+8))
                        log.info(indent..string.rep(" ",string.len(pos)+6).."}")
                    elseif (type(val)=="string") then
                        log.info(indent.."["..pos..'] => "'..val..'"')
                    else
                        log.info(indent.."["..pos.."] => "..tostring(val))
                    end
                end
            else
                log.info(indent..tostring(t))
            end
        end
    end
    if (type(t)=="table") then
        log.info(tostring(t).." {")
        sub_print_r(t,"  ")
        log.info("}")
    else
        sub_print_r(t,"  ")
    end
    log.info()
end



local function checksum(s, start_no, end_no)
	start_no = start_no or 1
	end_no = end_no or string.len(s)
	local ret,i=0,0
	for i=start_no,end_no do
		ret = (ret + string.byte(s,i)) % 256
	end
	return ret
end

--[[
函数名：parse
功能  ：按照帧结构解析处理一条完整的帧数据
参数  ：
		data：所有未处理的数据
返回值：第1个返回值是未处理的数据，第2个返回值是否继续处理,否则等待接收一段字符后再处理
]]
--起始，结束标志

local function parse(data)
	if not data then return end

	local headidx 
	local tailidx

	--无头尾的数据 直接返回
	if not string.find(data,string.char(0x0F)) and not string.find(data,string.char(0x1F))  then
		return "",false
	end

	------------------------------
	--有头0f 有尾f0f0f0f0  电池实时数据
	tailidx = string.find(data,string.char(0xF0,0xF0,0xF0,0xF0)) 
	if tailidx then 	
		headidx = string.find(data,string.char(0x0F,0x0F,0x0F,0x0F))	--起始标志 0f 0f 0f 0f
		if headidx then headidx=headidx+3 end
		while headidx do
			--设置设备DEVC_ID
			--local id_hidx = string.find(data,"DEVC_ID=") + 7 --总共8字节
			--if	id_hidx > 7 then
			--	local id_tidx = string.find(data,"]]]") 
			--	DEVC_ID = string.sub(data,id_hidx,id_tidx-id_hidx)
			--	write_cmd('prod_id.t2.txt="' + DEVC_ID +'"')
			--	end
			
			--有尾 满足长度 和 CRC	-- [直接返回]
			if tailidx-headidx>=23 and string.byte(data,tailidx-1)==checksum(data,headidx+1,tailidx-2) then  --字符长度超过23，CRC校验通过
				log.info("UART 0F0F0F0F F0F0F0F0 CRC ok",tostring(tailidx-headidx))
				
				--write_cmd('p0.cmd.txt="air bat OK"')
				--stmp = "bat_info get OK"	uart1.write_cmd(string.char(0xA5,0x5A,5+string.len(stmp),0x82,0x02,0x80)..stmp)    

				--succ,保存数据
				local j = headidx
				
				g_bat["cntl_x_bak"] = string.byte(data, j+1)    --控制信息
				g_bat["warn_x_bak"] = ( string.byte(data, j+2)*256 + string.byte(data, j+3) ) --告警信息
				
				g_bat["cntl_x"] = string.byte(data, j+1)    --控制信息
				g_bat["warn_x"] = ( string.byte(data, j+2)*256 + string.byte(data, j+3) ) --告警信息
				g_bat["Ah_left"] = ( string.byte(data, j+4)*256 + string.byte(data, j+5) ) --剩余电量
				g_bat["percent_left"] = string.byte(data, j+6) --剩余电量 % 比
				g_bat["T_max"] = string.byte(data,j+7)  --top温度
				g_bat["Power"] = string.byte(data,j+8)*256 + string.byte(data,j+9) --功率
				g_bat["V_total"] = (string.byte(data,j+10)*256 + string.byte(data,j+11)) --总电压
				g_bat["I_total"] = (string.byte(data,j+12)*256 + string.byte(data,j+13)) --总电流
				g_bat["I_charge"] = (string.byte(data,j+14)*256 + string.byte(data,j+15)) --充电电流    
				g_bat["I_discharge"] = (string.byte(data,j+16)*256 + string.byte(data,j+17)) --放电电流
				g_bat["T1"] = string.byte(data,j+18) --温度1
				g_bat["T2"] = string.byte(data,j+19) --温度2
				g_bat["T3"] = string.byte(data,j+20) --温度3
				g_bat["T4"] = string.byte(data,j+21) --温度4
				g_bat["T5"] = string.byte(data,j+22) --温度5
				g_bat["V_clamp"] = (string.byte(data,j+23)*256 + string.byte(data,j+24)) --电池1组
				g_bat["V"] = {}
				local i=0
				for i=j+25,tailidx-2-8,2 do
					table.insert( g_bat["V"], (string.byte(data,i)*256 + string.byte(data,i+1))) --电压
				end
				g_bat["days_left"] = (string.byte(data,tailidx-3)*256 + string.byte(data,tailidx-2)); --
				
				if g_bat["I_total"] > 0 and g_bat["I_discharge"] > 1 then
					g_dischInfo["discharge"] = g_bat["I_total"]
					g_dischInfo["Ah_left"] = g_bat["Ah_left"]
					g_dischInfo["ok"] = true
				end
				
				g_bat["batnew"]=true
				g_bat["batok"]=true 
				
				g_bat["bat_raw"] = ""
				for i=headidx,tailidx do
					g_bat["bat_raw"] = g_bat["bat_raw"] .. string.format("%02X ",string.byte(data,i))
				end	
				log.info("uart read jiangsy",g_bat["bat_raw"])
								
				return string.sub(data, tailidx+1, -1),true
			else 
				headidx = string.find(data,string.char(0x0F,0x0F,0x0F,0x0F),headidx+1)
				if headidx then headidx=headidx+3 end
			end
		end
		return string.sub(data, tailidx+1, -1),true
	end --end of if tailidx
	
	------------------------------	
	--[[有头1f 有尾f1f1f1f1
	tailidx = string.find(data,string.char(0xF1,0xF1,0xF1,0xF1)) 
	if tailidx then
		headidx = string.find(data,string.char(0x1F,0x1F,0x1F,0x1F))  --起始标志 1f 1f 1f 1f
		if headidx then headidx=headidx+3 end
		while headidx do
			--有尾 满足长度 和 CRC	-- [直接返回]
			if tailidx-headidx>=38 and string.byte(data,tailidx-1)==checksum(data,headidx+1,tailidx-2) then
				log.info("UART 1F1F1F1F F1F1F1F1 CRC ok")
				write_cmd('p0.cmd.txt="air parm OK"')
				--succ,保存数据
				g_bat["parm"] = {}
				for i=headidx,tailidx do
					table.insert( g_bat["parm"], string.byte(data,i) )
				end			
				g_bat["parmnew"] = true
				mqtt1.pubParmMsg()
				return string.sub(data, tailidx+1, -1),true  --数据串处理完后，下移处理
			else 
				headidx = string.find(data,string.char(0x1F,0x1F,0x1F,0x1F),headidx+1)
				if headidx then headidx=headidx+3 end
			end
		end
		return string.sub(data, tailidx+1, -1),true
	end --end of if tailidx
	
	
	--参数设置完成回复F1F1F1F2,1F1F1F2F
	--log.info("reply_receiv ",common.binstohexs(data))
	--write_cmd('run_info.run_t15.txt="reply_receiv ok"')
	--local buf = pack.pack("A", data)
	
	--有头1f 有尾f1f1f1f1
	tailidx = string.find(common.binstohexs(data),'0F2F2F2F0101F2F2F2F0') 
	----log.info("reply_receiv ",tailidx)
	
	if tailidx then
		mqtt1.reply_receiv = 2
		write_cmd('run_info.run_t15.txt="reply_receiv 2"')
		return string.sub(data, tailidx+1, -1),true
	end --end of if tailidx
	]]	
	------------------------------		
	--有头无尾 等待后续数据
	return data,false
	
end

--[[
函数名：proc
功能  ：处理从串口读到的数据
参数  ：
		data：当前一次从串口读到的数据
返回值：无
]]
local function proc(data)
	if not data or string.len(data) == 0 then return end
	--追加到缓冲区
	rdbuf = rdbuf..data

	local unproc,goon
	unproc = rdbuf
	--根据帧结构循环解析未处理过的数据
	while true do
		unproc,goon = parse(unproc)
		if not unproc or unproc == "" or not goon then
			break
		end
	end
	
	rdbuf = unproc or ""

end

--[[
函数名：read
功能  ：读取串口接收到的数据
参数  ：无
返回值：无
]]
local function read()
	local data = ""
	--底层core中，串口收到数据时：
	--如果接收缓冲区为空，则会以中断方式通知Lua脚本收到了新数据；
	--如果接收缓冲器不为空，则不会通知Lua脚本
	--所以Lua脚本中收到中断读串口数据时，每次都要把接收缓冲区中的数据全部读出，这样才能保证底层core中的新数据中断上来，此read函数中的while语句中就保证了这一点

	while true do
		data = uart.read(UART_ID,"*l",0)		-- uart.INF_TIMEOUT 接收前等待一段时间; 0 马上读取 不等待
		if not data or string.len(data) == 0 then break end
		--打开下面的打印会耗时
		--log.info("uart read",common.binstohexs(data))
		proc(data)
	end

end
--[[
函数名：write	功能 ：通过串口发送数据
参数  ：			s：要发送的数据
]]
function write(s)
	--log.info("write",s)
	uart.write(UART_ID,s)
end

--[[memory()
local function memory()
	collectgarbage("collect")
	local m = collectgarbage("count")
	log.info("MEM=", m .. "k")
	write_cmd('p0.cmd.txt="MEM='.. m ..'k"')
end

sys.timerLoopStart(memory,300000)	--300s一次

]]
local function refreshcmd()
	if g_bat["batnew"]==true then
		s = ('p0.cmd.txt="air bat OK"')
	else
		s = ('p0.cmd.txt="--"')
	end
	uart.write(UART_ID, "[[[["..  s .."]]]]")
end

function write_cmd(s)
--[[if string.len(s)>40 then
		local tmp=""
		for i=1,string.len(s) do
			tmp = tmp .. string.format("%02X ",string.byte(s,i))
		end	
		log.info("TXsetpm",tmp) 
	end
	log.info("TXcmd",s)
	if string.find(s,"p0.cmd.txt") then 
		sys.timerStopAll(refreshcmd)
		sys.timerStart(refreshcmd,8000)
	end ]]
	uart.write(UART_ID, "[[[["..  s .."]]]]") 	
	log.info("TXcmd",s)
end

--[[
--保持系统处于唤醒状态，此处只是为了测试需要，所以此模块没有地方调用pm.sleep("test")休眠，不会进入低功耗休眠状态
--在开发“要求功耗低”的项目时，一定要想办法保证pm.wake("test")后，在不需要串口时调用pm.sleep("test")
pm.wake("test")
--注册串口的数据接收函数，串口收到数据后，会以中断方式，调用read接口读取数据
sys.reguart(UART_ID,read)
--配置并且打开串口
--uart.setup(UART_ID,57600,9,uart.PAR_NONE,uart.STOP_1)

//sys.timerLoopStart(uart_runonce,10000)
]]

local function uartinit()
	--sys.reguart(UART_ID,read)		--注册中断接收函数
	g_bat["batnew"] = false
	g_bat["batok"] =false
	g_bat["parmnew"] =false
	--配置并且打开串口
	uart.setup(UART_ID,57600,8,uart.PAR_NONE,uart.STOP_1)
	--如果需要打开“串口发送数据完成后，通过异步消息通知”的功能，则使用下面的这行setup，注释掉上面的一行setup
	--uart.setup(UART_ID,115200,8,uart.PAR_NONE,uart.STOP_1,nil,1)
	write_cmd('p0.cmd.txt="AIR POWER ON"')
	write_cmd('main.main_msg.txt="AIR POWER ON"')
	uart1.write_cmd("cmd=air1")

end 

local function uartclose()
	uart.close(UART_ID)	
end

local function uartflush()
	while true do		--清空uart缓存
		local data = uart.read(UART_ID,"*l",0)
		if not data or string.len(data) == 0 then break end
	end
end

function packBAT()
	local datas={}
	
	if g_bat["batnew"] == true then 
		g_bat["batnew"] = false
		
		bat_tab = {
			id = "bat_info",
			datapoints = 
			{{
			  at 	= g_bat["time"],
			  value = {
				  cntl_x = g_bat["cntl_x"],
				  warn_x = g_bat["warn_x"],
				  --Ah_left = g_bat["Ah_left"]/10 ..'.'..  g_bat["Ah_left"]%10,
				  Ah_left = g_bat["Ah_left"]/10 ,
				  percent_left = g_bat["percent_left"],
				  T_max = g_bat["T_max"],
				  Power = g_bat["Power"],
				  --V_total = g_bat["V_total"]/10 ..'.'.. g_bat["V_total"]%10,
				  --I_total = g_bat["I_total"]/10 ..'.'.. g_bat["I_total"]%10,
				  --I_charge = g_bat["I_charge"]/100 ..'.'.. (g_bat["I_charge"]%100)/10 .. (g_bat["I_charge"]%100)%10,
				  --I_discharge = g_bat["I_discharge"]/100 ..'.'.. (g_bat["I_discharge"]%100)/10 .. (g_bat["I_discharge"]%100)%10, 
				  V_total = g_bat["V_total"]/10 ,
				  I_total = g_bat["I_total"]/10 ,
				  I_charge = g_bat["I_charge"]/100 ,
				  I_discharge = g_bat["I_discharge"]/100 , 
				  T1=g_bat["T1"], T2=g_bat["T2"], T3=g_bat["T3"], T4=g_bat["T4"], T5=g_bat["T5"], 
				  V = g_bat["V"],
				  V_clamp = g_bat["V_clamp"],
				  days_left = g_bat["days_left"],
				  --bat_raw = g_bat["bat_raw"],  //20190422
				  }
			}}
		}
		table.insert(datas, bat_tab)
			
		T_max_tab = { id = "T_max", datapoints = 
			{{	at	= g_bat["time"], 
				value = g_bat["T_max"]
			}}
		}
		table.insert(datas, T_max_tab)
	else
		return ""
	end
	if g_bat["cntl_x_bak"] ~= 208 or g_bat["warn_x_bak"] ~= 0 then
		warn_bak_tab = { id = "warn_bak", datapoints = 
			{{	at	= g_bat["time"], 
				value = g_bat["cntl_x_bak"] 
			}}
		}

		table.insert(datas, warn_bak_tab)
	end
	
	local send_tab =  { datastreams = datas }
	local msg = json.encode(send_tab)
	local len_l, len_h = msg.len(msg) % 256, msg.len(msg) / 256
	local buf = pack.pack("bbbA", 0x01,len_h,len_l,msg)
    return buf
end



--保持系统处于唤醒状态，此处只是为了测试需要，所以此模块没有地方调用pm.sleep("testUart")休眠，不会进入低功耗休眠状态
--在开发“要求功耗低”的项目时，一定要想办法保证pm.wake("testUart")后，在不需要串口时调用pm.sleep("testUart")
pm.wake("uart1")
--注册串口的数据接收函数，串口收到数据后，会以中断方式，调用read接口读取数据
uart.on(UART_ID,"receive",read)
--注册串口的数据发送通知函数
uart.on(UART_ID,"sent",writeOk)

sys.timerStart(uartinit,1000)
