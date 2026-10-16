-- v1; KEYS share {service-b}. ARGV: C,r tokens/sec,cost,maxConcurrent,leaseMs,uniqueLeaseId.
local C,r,cost,limit,lease = tonumber(ARGV[1]),tonumber(ARGV[2]),tonumber(ARGV[3]),tonumber(ARGV[4]),tonumber(ARGV[5])
local function positive(n) return n and n == n and n > 0 and n < 1000000000 end
if not positive(C) or not positive(r) or not positive(cost) or not positive(limit) or not positive(lease) then return redis.error_reply('INVALID_ARGUMENT') end
if limit ~= math.floor(limit) or lease < 100 or lease > 60000 or not ARGV[6] or #ARGV[6] < 16 then return redis.error_reply('INVALID_ARGUMENT') end
if cost > C then return {0,'0',-1,'COST_EXCEEDS_CAPACITY'} end
local clock = redis.call('TIME')
local now = tonumber(clock[1])*1000 + tonumber(clock[2])/1000
local state = redis.call('HMGET',KEYS[1],'tokens','ts','config')
local signature = ARGV[1]..':'..ARGV[2]..':'..ARGV[4]..':'..ARGV[5]
if state[3] and state[3] ~= signature then return redis.error_reply('CONFIG_MISMATCH') end
local previous = tonumber(state[2]) or now
local ts = math.max(now, previous)
local tokens = math.min(C,(tonumber(state[1]) or C) + r*math.max(0,now-previous)/1000)
redis.call('ZREMRANGEBYSCORE',KEYS[2],'-inf',now)
local inFlight = redis.call('ZCARD',KEYS[2])
local allowed,retry,reason = 0,0,'TOKEN'
if tokens >= cost and inFlight < limit then
 allowed=1; tokens=tokens-cost; reason='OK'
 redis.call('ZADD',KEYS[2],now+lease,ARGV[6])
 local lastLease=redis.call('ZRANGE',KEYS[2],-1,-1,'WITHSCORES')
 redis.call('PEXPIRE',KEYS[2],math.ceil(tonumber(lastLease[2])-now+1000))
else
 if tokens < cost then retry=math.ceil(math.max(0,previous-now)+(cost-tokens)*1000/r) end
 if inFlight >= limit then
  local earliest=redis.call('ZRANGE',KEYS[2],0,0,'WITHSCORES')
  retry=math.max(retry,math.ceil(tonumber(earliest[2])-now));reason='CONCURRENCY'
 end
end
redis.call('HSET',KEYS[1],'tokens',tostring(tokens),'ts',tostring(ts),'config',signature)
-- Only expires after even an empty bucket could be completely full; never resets early.
redis.call('PEXPIRE',KEYS[1],math.ceil(math.max(0,ts-now)+C/r*1000)+1000)
return {allowed,tostring(tokens),math.max(0,retry),reason}
