-- luacheck: globals core
local mmdb = require("mmdb")

local db_country, db_asn
local geo_ready = false

-- Интервалы (в секундах)
local RETRY_INTERVAL   = 60      -- между попытками, пока базы ещё не загружены
local REFRESH_INTERVAL = 3600    -- как часто переоткрывать уже загруженные базы (1ч)

local COUNTRY_PATH = "/var/lib/GeoIP/GeoLite2-Country.mmdb"
local ASN_PATH     = "/var/lib/GeoIP/GeoLite2-ASN.mmdb"

-- Открыть одну базу; возвращает handle или nil
local function open_db(path)
	local ok, r = pcall(mmdb.open, path)
	if ok and r then
		return r
	end
	return nil
end

-- Перечитать обе базы. Atomic-ish: меняем глобальные ссылки только при успехе.
-- Поскольку sidecar делает атомарный mv, на диске всегда валидный файл.
local function reload_dbs()
	local c = open_db(COUNTRY_PATH)
	local a = open_db(ASN_PATH)

	if c then
		db_country = c
	end
	if a then
		db_asn = a
	end

	if db_country and db_asn then
		if not geo_ready then
			core.log(core.info, "GeoIP databases loaded successfully.")
		else
			core.log(core.info, "GeoIP databases reloaded.")
		end
		geo_ready = true
		return true
	end

	return false
end

local function search(db, ip)
	if not db or not ip or ip == "" then
		return nil
	end
	local method = ip:match(":") and "search_ipv6" or "search_ipv4"
	local ok, r = pcall(db[method], db, ip)
	return ok and r or nil
end

local function mmdb_lookup(ip, db_type, ...)
	local db
	if db_type == "country" then
		db = db_country
	elseif db_type == "asn" then
		db = db_asn
	else
		return nil
	end

	local result = search(db, ip)
	if not result then
		return nil
	end

	local props = { ... }
	local obj = result
	if #props == 0 then
		if db_type == "asn" and result.autonomous_system_number then
			return "AS" .. result.autonomous_system_number
		end
		return nil
	else
		for _, key in ipairs(props) do
			if type(obj) == "table" and obj[key] then
				obj = obj[key]
			else
				return nil
			end
		end
		if db_type == "asn" and type(obj) == "number" then
			return "AS" .. obj
		else
			return tostring(obj)
		end
	end
end

core.register_converters("mmdb_lookup", function(ip, db_type, ...)
	return mmdb_lookup(ip, db_type, ...)
end)

core.register_fetches("geo_ready", function()
	if geo_ready then
		return "1"
	end
	return "0"
end)

-- Фоновая задача: дожидается появления баз, затем периодически переоткрывает их.
-- Запускается в каждом воркере независимо.
core.register_task(function()
	-- Фаза 1: ждём появления баз (sidecar может ещё качать)
	while not reload_dbs() do
		core.log(core.info, "GeoIP databases not ready yet, retrying...")
		core.msleep(RETRY_INTERVAL * 1000)
	end

	-- Фаза 2: периодический рефреш, чтобы подхватывать обновления от sidecar
	while true do
		core.msleep(REFRESH_INTERVAL * 1000)
		pcall(reload_dbs)
	end
end)
