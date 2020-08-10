MatchTeam teamCurrentlyPaused;

public bool Pauseable() {
  return g_GameState >= Get5State_KnifeRound && g_PausingEnabledCvar.BoolValue;
}

public Action Command_TechPause(int client, int args) {
  if (!g_AllowTechPauseCvar.BoolValue || !Pauseable() || IsPaused()) {
    return Plugin_Handled;
  }

  g_InExtendedPause = true;

  if (client == 0) {
    Pause();
    Get5_MessageToAll("%t", "AdminForceTechPauseInfoMessage");
    return Plugin_Handled;
  }

  Pause();
  Get5_MessageToAll("%t", "MatchTechPausedByTeamMessage", client);

  return Plugin_Handled;
}

public Action Command_Pause(int client, int args) {
  if (!Pauseable() || IsPaused()) {
    return Plugin_Handled;
  }

  int currentTimestamp = GetTime();

  if (g_cooldownTime[client] != -1 && g_cooldownTime[client] > currentTimestamp) {
    return Plugin_Handled;
  }

  g_cooldownTime[client] = currentTimestamp + 15;

  GetConVarString(g_PauseModeCvar, activePauseMode, sizeof(activePauseMode));

  if (StrEqual(activePauseMode, "Faceit", false)) {
    MatchTeam currentTeam = CSTeamToMatchTeam(GetClientTeam(client));
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
    int maxPauseTimeAllowed = g_MaxPauseTimeCvar.IntValue;

    if (maxPauseTimeAllowed > 0 && g_TeamPauseTimeUsed[currentTeam] >= maxPauseTimeAllowed) {
      Get5_Message(client, "You have no more timeout time remaining.");
      return Plugin_Handled;
    }

    ServerCommand("mp_pause_match");
    teamCurrentlyPaused = currentTeam;

    int timeLeft = maxPauseTimeAllowed - g_TeamPauseTimeUsed[currentTeam];
    int timeInMinutes = timeLeft / 60;
    int timeInSeconds = timeLeft % 60;

    int currentTeamIndex = -1;
    int index = -1;

    while ((index = FindEntityByClassname(index, "cs_team_manager"))) {
      int teamNumber = GetEntProp(index, Prop_Send, "m_iTeamNum");
      int csTeam = MatchTeamToCSTeam(currentTeam);
      if (teamNumber == csTeam) {
        currentTeamIndex = index
      }
    }

    char currentTeamName[32];
    GetEntPropString(currentTeamIndex, Prop_Send, "m_szClanTeamname", currentTeamName, 32);
    Get5_MessageToAll("%s has %i minute(s) %i second(s) left for pauses.", currentTeamName, timeInMinutes, timeInSeconds);

    pauseTimerHandler = CreateTimer(1.0, Timer_PauseTimeCheck, currentTeam, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Handled;
  }
}

public Action Timer_PauseTimeCheck(Handle timer, int data) {
  if (!Pauseable() || !IsPaused() || g_FixedPauseTimeCvar.BoolValue) {
    return Plugin_Stop;
  }

  // Unlimited pause time.
  if (g_MaxPauseTimeCvar.IntValue <= 0) {
    return Plugin_Stop;
  }

  char pausePeriodString[32];
  if (g_ResetPausesEachHalfCvar.BoolValue) {
    Format(pausePeriodString, sizeof(pausePeriodString), " %t", "PausePeriodSuffix");
  }

  MatchTeam team = view_as<MatchTeam>(data);
  int timeLeft = g_MaxPauseTimeCvar.IntValue - g_TeamPauseTimeUsed[team];

  // Only count against the team's pause time if we're actually in the freezetime
  // pause and they haven't requested an unpause yet.
  if (InFreezeTime() && !g_TeamReadyForUnpause[team]) {
    g_TeamPauseTimeUsed[team]++;

    if (timeLeft == 10) {
      Get5_MessageToAll("%t", "PauseTimeExpiration10SecInfoMessage", g_FormattedTeamNames[team]);
    } else if (timeLeft % 30 == 0) {
      Get5_MessageToAll("%t", "PauseTimeExpirationInfoMessage", g_FormattedTeamNames[team],
                        timeLeft, pausePeriodString);
    }
  }

  if (timeLeft <= 0) {
    Get5_MessageToAll("%t", "PauseRunoutInfoMessage", g_FormattedTeamNames[team]);
    Unpause();
    return Plugin_Stop;
  }

  return Plugin_Continue;
}

public Action Command_Unpause(int client, int args) {
  if (!IsPaused())
    return Plugin_Handled;

  // Let console force unpause
  if (client == 0) {
    Unpause();
    Get5_MessageToAll("%t", "AdminForceUnPauseInfoMessage");
    return Plugin_Handled;
  }

  if (g_FixedPauseTimeCvar.BoolValue && !g_InExtendedPause) {
    return Plugin_Handled;
  }

  MatchTeam team = GetClientMatchTeam(client);
  g_TeamReadyForUnpause[team] = true;

  if (g_TeamReadyForUnpause[MatchTeam_Team1] && g_TeamReadyForUnpause[MatchTeam_Team2]) {
    Unpause();
    if (IsPlayer(client)) {
      Get5_MessageToAll("%t", "MatchUnpauseInfoMessage", client);
    }
  } else if (g_TeamReadyForUnpause[MatchTeam_Team1] && !g_TeamReadyForUnpause[MatchTeam_Team2]) {
    Get5_MessageToAll("%t", "WaitingForUnpauseInfoMessage", g_FormattedTeamNames[MatchTeam_Team1],
                      g_FormattedTeamNames[MatchTeam_Team2]);
  } else if (!g_TeamReadyForUnpause[MatchTeam_Team1] && g_TeamReadyForUnpause[MatchTeam_Team2]) {
    Get5_MessageToAll("%t", "WaitingForUnpauseInfoMessage", g_FormattedTeamNames[MatchTeam_Team2],
                      g_FormattedTeamNames[MatchTeam_Team1]);
  }

  return Plugin_Handled;
}