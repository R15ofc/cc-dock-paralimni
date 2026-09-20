return function(car, context)
  local MEDIA_RELEASE = "9e05ee129d8299bfc623f09224baf61ba0d1c313"
  local MEDIA_BASE = "https://raw.githubusercontent.com/R15ofc/cc-dock-paralimni/"
    .. MEDIA_RELEASE .. "/media/music/"
  local BUFFER_SIZE = 16 * 1024

  local catalog = {
    { id = "moonlight", title = "Moonlight Sonata", artist = "Ludwig van Beethoven",
      duration = 306.672, file = "moonlight.dfpwm" },
    { id = "mozart", title = "Eine kleine Nachtmusik", artist = "Wolfgang Amadeus Mozart",
      duration = 252.587, file = "mozart.dfpwm" },
    { id = "bach-air", title = "Air", artist = "Johann Sebastian Bach",
      duration = 259.898, file = "bach-air.dfpwm" },
    { id = "chopin-nocturne", title = "Nocturne Op. 9 No. 2", artist = "Frederic Chopin",
      duration = 203.346, file = "chopin-nocturne.dfpwm" },
    { id = "vivaldi-spring", title = "Spring: Allegro", artist = "Antonio Vivaldi",
      duration = 215.280, file = "vivaldi-spring.dfpwm" },
    { id = "clair-de-lune", title = "Clair de lune", artist = "Claude Debussy",
      duration = 304.087, file = "clair-de-lune.dfpwm" },
    { id = "gymnopedie", title = "Gymnopedie No. 1", artist = "Erik Satie",
      duration = 204.799, file = "gymnopedie.dfpwm" },
    { id = "fur-elise", title = "Fur Elise", artist = "Ludwig van Beethoven",
      duration = 160.446, file = "fur-elise.dfpwm" },
    { id = "brahms-dance", title = "Hungarian Dance No. 5", artist = "Johannes Brahms",
      duration = 227.733, file = "brahms-dance.dfpwm" },
    { id = "pachelbel-canon", title = "Canon in D", artist = "Johann Pachelbel",
      duration = 201.065, file = "pachelbel-canon.dfpwm" }
  }
  local engineTrack = {
    id = "engine-five-cylinder",
    title = "Five-cylinder engine",
    artist = "Jonas Tittmann",
    duration = 32.600,
    file = "engine-five-cylinder.dfpwm"
  }

  local player = {
    catalog = catalog,
    currentIndex = 1,
    playing = false,
    repeatMode = "all",
    favouritesOnly = false,
    favourites = {},
    page = 1,
    volume = 0.85,
    engineSounds = true,
    sourceType = nil,
    handle = nil,
    decoder = nil,
    speaker = nil,
    speakerName = nil,
    pendingAudio = nil,
    awaitingSpeaker = false,
    startedAt = nil,
    notification = nil,
    lastSpeakerScan = -1e9,
    error = nil
  }

  local function statePath()
    local root = type(context.userRoot) == "function" and context.userRoot() or nil
    if not root then return nil end
    return fs.combine(root, "data/music.json")
  end

  local function notify(title, text)
    player.notification = {
      title = tostring(title or "Music"),
      text = tostring(text or ""),
      expires = os.clock() + 4.0
    }
  end

  local function save()
    local path = statePath()
    if not path or type(context.writeJson) ~= "function" then return false end
    local favouriteIds = {}
    for id, enabled in pairs(player.favourites) do
      if enabled then favouriteIds[#favouriteIds + 1] = id end
    end
    table.sort(favouriteIds)
    return context.writeJson(path, {
      favourites = favouriteIds,
      repeatMode = player.repeatMode,
      favouritesOnly = player.favouritesOnly,
      volume = player.volume,
      engineSounds = player.engineSounds,
      currentIndex = player.currentIndex
    })
  end

  function player:reload()
    local path = statePath()
    local data = path and type(context.readJson) == "function" and context.readJson(path) or nil
    self.favourites = {}
    if type(data) == "table" then
      if type(data.favourites) == "table" then
        for _, id in pairs(data.favourites) do self.favourites[tostring(id)] = true end
      end
      if data.repeatMode == "off" or data.repeatMode == "all" or data.repeatMode == "one" then
        self.repeatMode = data.repeatMode
      end
      self.favouritesOnly = data.favouritesOnly and true or false
      self.volume = math.max(0.1, math.min(1.0, tonumber(data.volume) or self.volume))
      self.engineSounds = data.engineSounds ~= false
      self.currentIndex = math.max(1, math.min(#catalog, math.floor(tonumber(data.currentIndex) or 1)))
    end
    return true
  end

  function player:discoverSpeaker(force)
    local now = os.clock()
    if not force and self.speaker and now - self.lastSpeakerScan < 2 then return self.speaker end
    self.lastSpeakerScan = now
    self.speaker, self.speakerName = nil, nil
    if not peripheral or type(peripheral.getNames) ~= "function" then return nil end
    local ok, names = pcall(peripheral.getNames)
    if not ok or type(names) ~= "table" then return nil end
    table.sort(names)
    for _, name in ipairs(names) do
      local typeOK, kind = pcall(peripheral.getType, name)
      if typeOK then
        local isSpeaker = kind == "speaker"
        if type(kind) == "table" then
          for _, value in pairs(kind) do if value == "speaker" then isSpeaker = true end end
        end
        if isSpeaker then
          self.speakerName = name
          self.speaker = peripheral.wrap(name)
          break
        end
      end
    end
    return self.speaker
  end

  function player:closeStream(stopSpeaker)
    if self.handle then pcall(function() self.handle.close() end) end
    if stopSpeaker and self.speaker and type(self.speaker.stop) == "function" then
      pcall(self.speaker.stop)
    end
    self.handle = nil
    self.decoder = nil
    self.pendingAudio = nil
    self.awaitingSpeaker = false
    self.sourceType = nil
    self.startedAt = nil
  end

  function player:current()
    return catalog[self.currentIndex]
  end

  function player:visibleTracks()
    local tracks = {}
    for index, track in ipairs(catalog) do
      if not self.favouritesOnly or self.favourites[track.id] then
        tracks[#tracks + 1] = { index = index, track = track }
      end
    end
    return tracks
  end

  function player:queueAudio()
    if not self.handle or not self.decoder or not self.speaker then return false end
    if self.awaitingSpeaker then return true end
    if not self.pendingAudio then
      local readOK, chunk = pcall(self.handle.read, BUFFER_SIZE)
      if not readOK then
        self.error = tostring(chunk)
        self:finishStream()
        return false
      end
      if not chunk then
        self:finishStream()
        return true
      end
      local decodeOK, samples = pcall(self.decoder, chunk)
      if not decodeOK then
        self.error = tostring(samples)
        self:finishStream()
        return false
      end
      self.pendingAudio = samples
    end
    local playOK, accepted = pcall(self.speaker.playAudio, self.pendingAudio, self.volume)
    if not playOK then
      self.error = tostring(accepted)
      self:closeStream(false)
      notify("Audio unavailable", self.error)
      return false
    end
    self.awaitingSpeaker = true
    if accepted then self.pendingAudio = nil end
    return true
  end

  function player:startStream(track, sourceType, announce)
    if not track then return false end
    if not self:discoverSpeaker(false) then
      self.error = "Connect a speaker"
      notify("Music", self.error)
      return false
    end
    if not http or type(http.get) ~= "function" then
      self.error = "HTTP API is disabled"
      notify("Music", self.error)
      return false
    end
    local decoderOK, dfpwm = pcall(require, "cc.audio.dfpwm")
    if not decoderOK or type(dfpwm) ~= "table" or type(dfpwm.make_decoder) ~= "function" then
      self.error = "DFPWM decoder unavailable"
      notify("Music", self.error)
      return false
    end

    self:closeStream(true)
    local responseOK, response = pcall(http.get, MEDIA_BASE .. track.file, nil, true)
    if not responseOK or not response then
      self.error = tostring(response or "Download failed")
      notify("Music unavailable", self.error)
      return false
    end
    self.handle = response
    self.decoder = dfpwm.make_decoder()
    self.sourceType = sourceType
    self.playing = sourceType == "music"
    self.startedAt = os.clock()
    self.error = nil
    if announce then notify("Now playing", track.title .. " — " .. track.artist) end
    return self:queueAudio()
  end

  function player:play(index)
    index = math.max(1, math.min(#catalog, math.floor(tonumber(index) or self.currentIndex)))
    self.currentIndex = index
    self.page = math.max(1, math.ceil(index / 4))
    save()
    return self:startStream(catalog[index], "music", true)
  end

  function player:stop()
    self.playing = false
    self:closeStream(true)
    notify("Music", "Playback stopped")
    return true
  end

  function player:playlistPosition()
    local tracks = self:visibleTracks()
    for position, item in ipairs(tracks) do
      if item.index == self.currentIndex then return tracks, position end
    end
    return tracks, 0
  end

  function player:step(direction)
    local tracks, position = self:playlistPosition()
    if #tracks == 0 then
      self.favouritesOnly = false
      tracks, position = self:playlistPosition()
    end
    if #tracks == 0 then return false end
    if position < 1 then position = 1 else position = position + direction end
    if position < 1 then position = #tracks end
    if position > #tracks then position = 1 end
    return self:play(tracks[position].index)
  end

  function player:finishStream()
    local sourceType = self.sourceType
    self:closeStream(false)
    if sourceType == "engine" then return end
    if sourceType ~= "music" then return end
    if self.repeatMode == "one" then
      self:startStream(self:current(), "music", true)
    elseif self.repeatMode == "all" then
      self:step(1)
    else
      self.playing = false
      notify("Music", "Playlist finished")
    end
  end

  function player:toggleFavourite(index)
    index = math.max(1, math.min(#catalog, math.floor(tonumber(index) or self.currentIndex)))
    local track = catalog[index]
    self.favourites[track.id] = not self.favourites[track.id]
    save()
    notify(self.favourites[track.id] and "Added to favourites" or "Removed from favourites", track.title)
    return true
  end

  function player:cycleRepeat()
    if self.repeatMode == "off" then self.repeatMode = "all"
    elseif self.repeatMode == "all" then self.repeatMode = "one"
    else self.repeatMode = "off" end
    save()
    notify("Repeat", self.repeatMode == "one" and "Current track" or self.repeatMode)
    return self.repeatMode
  end

  function player:toggleFavouritesView()
    self.favouritesOnly = not self.favouritesOnly
    self.page = 1
    save()
    return self.favouritesOnly
  end

  function player:cycleVolume()
    if self.volume < 0.6 then self.volume = 0.85
    elseif self.volume < 0.95 then self.volume = 1.0
    else self.volume = 0.45 end
    save()
    notify("Volume", tostring(math.floor(self.volume * 100 + 0.5)) .. "%")
    return self.volume
  end

  function player:toggleEngineSounds()
    self.engineSounds = not self.engineSounds
    if not self.engineSounds and self.sourceType == "engine" then self:closeStream(true) end
    save()
    notify("Engine sound", self.engineSounds and "On" or "Off")
    return self.engineSounds
  end

  function player:engineWanted()
    return self.engineSounds and car.state
      and (not car.state.driveEngineOff or not car.state.workshopEngineOff)
  end

  function player:update()
    if self.notification and os.clock() >= (tonumber(self.notification.expires) or 0) then
      self.notification = nil
    end
    self:discoverSpeaker(false)
    if self.playing then return end
    if self:engineWanted() then
      if self.sourceType ~= "engine" then self:startStream(engineTrack, "engine", false) end
    elseif self.sourceType == "engine" then
      self:closeStream(true)
    end
  end

  function player:handleEvent(event, name)
    if event == "speaker_audio_empty" and self.speaker then
      if self.speakerName and name and tostring(name) ~= tostring(self.speakerName) then return false end
      self.awaitingSpeaker = false
      return self:queueAudio()
    end
    if event == "peripheral" or event == "peripheral_detach" then
      self:discoverSpeaker(true)
    end
    return false
  end

  function player:snapshot()
    local track = self:current()
    local elapsed = self.playing and self.startedAt and math.max(0, os.clock() - self.startedAt) or 0
    local notification = self.notification
    if notification and os.clock() >= (tonumber(notification.expires) or 0) then notification = nil end
    return {
      playing = self.playing,
      title = track and track.title or "No track",
      artist = track and track.artist or "",
      currentIndex = self.currentIndex,
      favourite = track and self.favourites[track.id] and true or false,
      repeatMode = self.repeatMode,
      favouritesOnly = self.favouritesOnly,
      volume = self.volume,
      engineSounds = self.engineSounds,
      elapsed = elapsed,
      duration = track and track.duration or 0,
      speaker = self.speakerName,
      error = self.error,
      notification = notification
    }
  end

  player:reload()
  player:discoverSpeaker(true)
  car.music = player
  return player
end
