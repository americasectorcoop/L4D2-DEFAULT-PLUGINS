#include <sourcemod>
#include <sdktools>
#include <glow>
#include <colors>
#include <left4dhooks>
#include <regex>

#if SOURCEMOD_V_MINOR < 7
 #error Old version sourcemod!
#endif
#pragma newdecls required

#define DATA "01/15/2017"
#define PLUGIN_VERSION "2.1"
#define CVAR_FLAGS 0 // FCVAR_PLUGIN|FCVAR_NOTIFY
#define MAXLENGTH 128

#define ASC_PLAYER_PRO 5000 

#define TEAM_SURVIVORS 2
#define TEAM_INFECTED 3

#define ZC_TANK 8

#define UNLOCK 0
#define LOCK 1

#define STARTROOM_MAX_DIST		1000
#define FLAG_IGNORE_USE			32768

#define SAFEDOOR_MODEL_01 "checkpoint_door_01.mdl"
#define SAFEDOOR_MODEL_02 "checkpoint_door_-01.mdl"

#define PANIC_SOUND "npc/mega_mob/mega_mob_incoming.wav"
#define SOUND_VOTE_SELECT	"ui/alert_clink.wav"
#define SOUND_VOTE_WINNER	"ui/critical_event_1.wav"
#define SOUND_VOTE_LOSER	"ui/beep_error01.wav"


#define TIME_TO_DIE 92
#define TIME_FOR_NEXT_TRY 5

// ConVar sm_ar_announce;
// ConVar sm_ar_lock_tankalive;
ConVar sm_ar_DoorLock;
// ConVar sm_ar_AntySpam;
// ConVar g_hCvarCountdown;
Handle g_hTimer; 
int g_iClock;

int g_iUseCounter;
int g_iCountDown;
int g_iSecs;
int g_iPlayerUseCounter[MAXPLAYERS+1];
bool g_bInSafeRoom[MAXPLAYERS+1];
float g_GameTime[MAXPLAYERS + 1];
float g_fSec = 3.0;

bool g_bIsTimerOpen;
bool g_bIsAntifarmOn;
bool g_bTempBlock;
bool g_IsFinalMap;
bool g_IsFirstMap;
bool g_IsStandartMap;

int g_iSafetyLock;
int g_iIdKeyman;
int g_iIdGoal;

char MapName[55];
char SoundNotice[MAXLENGTH] = "doors/latchlocked2.wav";
char SoundDoorOpen[MAXLENGTH] = "doors/door_squeek1.wav";

static int g_iYesCount = 0;
static int g_iNoCount = 0;
static int g_iVoters = 0;
static int g_iPlayers = 0;
static bool g_bAllVoted = false;
ConVar g_hTimout;
int g_iSeconds;

int DOOR_LOCKED_COLOR[3] = { 244, 67, 54 };
int DOOR_UNLOCKED_COLOR[3] = { 76, 175, 80 };

public Plugin myinfo = 
{
  name = "[L4D2] Keyman",
  author = "Base by ztar, SupermenCJ, Aleexxx",
  description = "Only Keyman can open saferoom door.",
  version = PLUGIN_VERSION,
  url = "http://www.americasectorcoop.org"
}

public void OnPluginStart() {
  
  g_hTimout = CreateConVar("sm_ar_request_timout", "20.0", "", CVAR_FLAGS, true, 5.0, true, 30.0);
  
  // sm_ar_announce = CreateConVar("sm_ar_announce","1", "Announce plugin info(0:OFF 1:ON)", CVAR_FLAGS);
  // sm_ar_lock_tankalive = CreateConVar("sm_ar_lock_tankalive","0", "Lock door if any Tank is alive(0:OFF 1:ON)", CVAR_FLAGS);
  sm_ar_DoorLock = CreateConVar("sm_ar_doorlock_sec", "60", "number of g_iSeconds", CVAR_FLAGS, true, 5.0, true, 300.0);
  // sm_ar_AntySpam = CreateConVar("sm_ar_door_lock_spam", "5", "Survivors can close the door one time per <your choice> sec");
  // g_hCvarCountdown = CreateConVar("sm_time", "92", "Time to kill the players who do not get into the run. (0 = Off the plugin,> 0 = Enable)", CVAR_FLAGS, true, 0.0);
  ConVar cvar = CreateConVar("anti_console_flood", "3.0", "The door can be pulled no more than 7 times in 'x' sec without any consequences for the player", CVAR_FLAGS, true, 0.1, true, 10.0);
  g_fSec = cvar.FloatValue;
  HookEvent("player_death", Event_Player_Death);
  HookEvent("player_use", Event_Player_Use);
  HookEvent("round_start", Event_Round_Start);
  HookEvent("player_team", Event_Join_Team);
  HookEvent("player_spawn", Event_PlayerSpawn);
  HookEvent("item_pickup", Event_RoundStartAndItemPickup);
  HookEvent("bot_player_replace", OnBotPlayerReplace);
  HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
  HookEvent("mission_lost", Event_RoundEnd, EventHookMode_PostNoCopy);
  HookEvent("map_transition", Event_RoundEnd, EventHookMode_PostNoCopy);// esto estaba comentado no se porque xD
  HookEvent("player_left_checkpoint", OnPlayerLeftCheckpoint);
  HookEvent("player_entered_checkpoint", OnPlayerEnteredCheckpoint);
  
  RegAdminCmd("sm_initdoor", Command_InintDoor, ADMFLAG_CONFIG);
  RegAdminCmd("sm_checkweapons", Command_CheckWeapons, ADMFLAG_CONFIG);
  
  //AutoExecConfig(true, "l4d2_anti-runner");
}

native int TYSTATS_GetPoints(int client);

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
  MarkNativeAsOptional("TYSTATS_GetPoints");
  return APLRes_Success;
}

public void OnMapStart()
{
  /* Precache */
  PrecacheSound(SoundNotice, true);
  PrecacheSound(SoundDoorOpen, true);
  PrecacheSound("ambient/alarms/klaxon1.wav", true);
  PrecacheSound(PANIC_SOUND, true);
  PrecacheSound(SOUND_VOTE_SELECT, true);
  PrecacheSound(SOUND_VOTE_WINNER, true);
  PrecacheSound(SOUND_VOTE_LOSER, true);
  
  GetCurrentMap(MapName, sizeof(MapName));
  
  g_IsFirstMap = L4D_IsFirstMapInScenario();
  g_IsStandartMap = b_StandartMap();
  g_IsFinalMap = L4D_IsMissionFinalMap();
  
  ResetTimer();
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
  ResetTimer();
}

public void cvar_changed(ConVar convar, const char[] oldValue, const char[] newValue)
{
  g_fSec = StringToFloat(newValue);
  if (g_fSec == 0.0 || g_fSec < 3.0 || g_fSec > 7.0) 
  {
    convar.SetFloat(3.0);
    return;
  }
}

public Action Event_Join_Team(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  int clientTeam = GetEventInt(event, "team");
  bool isBot = GetEventBool(event, "isbot");
  
  if (!IsValidEntity(client) || isBot == true) return;
  
  if (clientTeam == 2)
  {
    SelectKeyman();
  }
}

public void OnClientDisconnect(int client)
{
  if (!IsValidEntity(client))
  {
    return;
  }
  
  if (client == g_iIdKeyman)
  {
    SelectKeyman();
  }
}

public Action Event_Round_Start(Event event, const char[] name, bool dontBroadcast)
{
  g_bIsAntifarmOn = false;
  g_iUseCounter = 0;
  g_bIsTimerOpen = false;
  g_bTempBlock = false;
  g_iSecs = 120;

  for(int i = 1; i <= MaxClients; i++)
  {
    if (IsValidEntity(i))
    {
      if (IsClientInGame(i))
      {
        g_iPlayerUseCounter[i] = 0;
        
        if (GetClientTeam(i) == 2)
        {
          g_bInSafeRoom[i] = false;
        }
      }
    }
  }
  CreateTimer(30.0, RoundStartDelay);
}

public void OnClientConnected(int client) 
{
  g_iPlayerUseCounter[client] = 0;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  
  if (client > 0 && IsClientInGame(client) && GetClientTeam(client) == 2 && IsValidEntity(client))
  {
    CreateTimer(1.2, TimerCheckSafeRoom, client, TIMER_FLAG_NO_MAPCHANGE);
  }
  return Plugin_Continue;
}

public Action OnBotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
  TimerCheckSafeRoom(INVALID_HANDLE, GetClientOfUserId(GetEventInt(event, "player")));
  return Plugin_Continue;
}

public Action TimerCheckSafeRoom(Handle timer, any client)
{
  if (client <= 0 || !IsClientConnected(client) || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2)
  {
    return Plugin_Stop;
  }

  float vec[3];
  float vecPlayer[3];
  GetClientAbsOrigin(client, vecPlayer);

  for(int i = 1;i <= MaxClients;i++)
  {
    if (client != i && g_bInSafeRoom[i] && IsClientConnected(i) && IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
    {
      GetClientAbsOrigin(i, vec);
      if (FloatAbs(vec[0] - vecPlayer[0]) + FloatAbs(vec[1] - vecPlayer[1]) + FloatAbs(vec[2] - vecPlayer[2]) < 500.0)
      {
        g_bInSafeRoom[client] = true;
        break;
      }
    }		
  }
  
  return Plugin_Stop;
}

public Action Event_RoundStartAndItemPickup(Event event, const char[] name, bool dontBroadcast)
{
  if (g_bTempBlock)
  {
    return;
  }

  g_bTempBlock = true;
  CreateTimer(1.0, LockSafeRoom, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action LockSafeRoom(Handle timer) {
  if (g_IsFinalMap || StrEqual(MapName, "c10m3_ranchhouse", false) || StrEqual(MapName, "nt03_moria", false)) {
    return;
  }
  float vSurvivor[3];
  float vDoor[3];
  if (StrEqual(MapName, "c5m1_waterfront", false) || 
    StrEqual(MapName, "c7m1_docks", false) || 
    StrEqual(MapName, "c10m1_caves", false) || 
    StrEqual(MapName, "l4d_yama_2", false)) {
    int Entity = -1;
    while((Entity = FindEntityByClassname(Entity, "prop_door_rotating_checkpoint")) != -1) {
      char model[255];
      GetEntPropString(Entity, Prop_Data, "m_ModelName", model, sizeof(model));
      if (StrContains(model, SAFEDOOR_MODEL_01, false) != -1 || StrContains(model, SAFEDOOR_MODEL_02, false) != -1) {
        continue;
      }
      if (GetEntProp(Entity, Prop_Data, "m_hasUnlockSequence") == UNLOCK) {
        g_iIdGoal = Entity;
        ControlDoor(Entity, LOCK);
        break;
      }
    }
    g_iSafetyLock = LOCK;
    return;
  }
  for(int i = 1;i <= MaxClients;i++) {
    if (IsClientInGame(i) && GetClientTeam(i) == TEAM_SURVIVORS) {
      GetClientAbsOrigin(i, vSurvivor);
      if (vSurvivor[0] != 0 && vSurvivor[1] != 0 && vSurvivor[2] != 0) {
        break;
      }
    }
  }
  int iEnt = -1;
  while ((iEnt = FindEntityByClassname(iEnt, "prop_door_rotating_checkpoint")) != INVALID_ENT_REFERENCE) {
    char model[255];
    GetEntPropString(iEnt, Prop_Data, "m_ModelName", model, sizeof(model));
    if (StrContains(model, SAFEDOOR_MODEL_01, false) != -1 || StrContains(model, SAFEDOOR_MODEL_02, false) != -1) {
      continue;
    }
    if (GetEntProp(iEnt, Prop_Data, "m_spawnflags") == FLAG_IGNORE_USE) {
      continue;
    }
    GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vDoor);
    if (GetVectorDistance(vSurvivor, vDoor) < STARTROOM_MAX_DIST) {
      continue;
    }
    g_iIdGoal = iEnt;
    ControlDoor(iEnt, LOCK);
    break;
  }
  g_iSafetyLock = LOCK;
}

public Action Command_InintDoor(int client, int args)
{
  CreateTimer(1.0, LockSafeRoom, _, TIMER_FLAG_NO_MAPCHANGE);
  SelectKeyman();
}

public Action RoundStartDelay(Handle timer, any client)
{
  SelectKeyman();
}

/**
 * Metodo para selecciona al keyman
 * return void
 */
public void SelectKeyman() {
  int players_noobs[MAXPLAYERS+1];
  int players_pro[MAXPLAYERS+1];
  int counterPro = 0, counterNoob = 0;
  // Recorriendo clientes
  for(int i = 1;i <= MaxClients; i++) {
    // Verificando entidad
    if (IsValidEntity(i)) {
      // Verificando si el cliente esta en juego
      if(IsClientInGame(i)) {
        // Verificando si el jugador esta vivo
        if(IsPlayerAlive(i)) {
          // Verificando si el cliente es real
          if(!IsFakeClient(i)) {
            // Verificando si el cliente es del equipo de sobrevivientes
            if (GetClientTeam(i) == TEAM_SURVIVORS) {
              // Verificando que el jugador sea pro
              if(TYSTATS_GetPoints(i) >= ASC_PLAYER_PRO) {
                players_pro[counterPro] = i;
                counterPro++;
              } else {
                players_noobs[counterNoob] = i;
                counterNoob++;
              }
            }
          }
        }
      }
    }
  }
  // Verificando cuantos players pro existen
  if (counterPro > 0) {
    int key = GetRandomInt(0, counterPro-1);
    g_iIdKeyman = players_pro[key];
  // Verificando cuantos noobs existen
  } else if (counterNoob > 0) {
    int key = GetRandomInt(0, counterNoob-1);
    g_iIdKeyman = players_noobs[key];
  }
}

public Action Event_Player_Death(Event event, const char[] name, bool dontBroadcast) {
  int victim = GetClientOfUserId(GetEventInt(event, "userid"));
  if (victim == g_iIdKeyman) {
    SelectKeyman();
  }
  return Plugin_Continue;
}

public Action Event_Player_Use(Event event, const char[] name, bool dontBroadcast) {
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  int Entity = GetEventInt(event, "targetid");
  
  if (IsValidEntity(Entity) && (g_iSafetyLock == LOCK) && (Entity == g_iIdGoal) && !g_IsFinalMap)
  {
    char entname[MAXLENGTH];
    if (GetEdictClassname(Entity, entname, sizeof(entname)))
    {
      if (StrEqual(entname, "prop_door_rotating_checkpoint"))
      {
        float fSec = GetGameTime();
        g_iPlayerUseCounter[client]++;
        g_GameTime[client] = fSec;
        
        if (g_iPlayerUseCounter[client] > 7)
        {
          if ((fSec - g_GameTime[client]) < g_fSec)
          {
            g_iPlayerUseCounter[client] = 0;
            SlapPlayer(client, 0, false);
          }
          else
          {
            g_iPlayerUseCounter[client] = 0;
          }
        }
          
        if (!g_bIsTimerOpen)
        {
          g_iUseCounter++;
          CheckUseCounter();
        }
        
        if (IsTankAlive())
        {
          EmitSoundToAll(SoundNotice, Entity);
          PrintHintText(client, "All tanks must be killed first");
          return Plugin_Continue;
        }
        
        AcceptEntityInput(Entity, "Lock");
        SetEntProp(Entity, Prop_Data, "m_hasUnlockSequence", LOCK);
        
        if (!IsValidEntity(g_iIdKeyman) || !IsClientInGame(g_iIdKeyman) || !IsPlayerAlive(g_iIdKeyman) || IsFakeClient(g_iIdKeyman))
        {
          SelectKeyman();
        }
        
        if (g_bIsAntifarmOn)
        {
          if (!g_bIsTimerOpen)
          {
            if (client == g_iIdKeyman)
            {
              g_bIsTimerOpen = true;
              
              if (g_iCountDown > g_iSecs)
              {
                g_iCountDown = g_iSecs + 40;
              }
              
              CreateTimer(1.0, TimerDoorCountDown, Entity, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
              
              CPrintToChatAll("\x04[\x05KEYMAN\x04] {blue}%N \x01unlock the safe room door", g_iIdKeyman);
              
            }
            else
            {
              if (GetRandomInt(1, 75) == 1)
              {
                g_bIsTimerOpen = true;
                
                if (g_iCountDown > g_iSecs)
                {
                  g_iCountDown = g_iSecs + 40;
                }
                
                CreateTimer(1.0, TimerDoorCountDown, Entity, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
                
                CPrintToChatAll("\x04[\x05KEYMAN\x04] {blue}%s \x01break open the safe room door", client);
              }
              else
              {
                EmitSoundToAll(SoundNotice, Entity);
                if (GetRandomInt(1, 5) == 1)
                {
                  PrintHintTextToAll("The Keyman is %N.\n Only the Keyman can open the door!", g_iIdKeyman);
                }
                else
                {
                  PrintHintText(client, "The keyman is: %N.\nTry to open the door again", g_iIdKeyman);
                }
              }
            }
          }
          else
          {
            if (GetRandomInt(1, 5) == 1)
            {
              PrintHintText(client, "The door is already unlocked!\nPlease wait for it %d seconds.", g_iCountDown);
            }
          }
        }
        else
        {
          if	(client == g_iIdKeyman)
          {				
            if (g_iUseCounter > 1)
            {

              if (!g_bIsTimerOpen)
              {
                g_bIsTimerOpen = true;
                if (g_iCountDown > g_iSecs)
                {
                  g_iCountDown = g_iSecs + 40;
                }
                CreateTimer(1.0, TimerDoorCountDown, Entity, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
                CPrintToChatAll("\x04[\x05KEYMAN\x04] {blue}%N \x01unlock the safe room door!", g_iIdKeyman);
              }
            }
          }
          else
          {
            if (!g_bIsTimerOpen)
            {
              EmitSoundToAll(SoundNotice, Entity);
              if (GetRandomInt(1, 5) == 1)
              {
                PrintHintTextToAll("The keyman is: %N.\nOnly the keyman can open the door.", g_iIdKeyman);
              }
              else
              {
                PrintHintText(client, "The keyman is: %N.\nOnly the keyman can open the door.", g_iIdKeyman);
              }
            }
            else
            {
              if (GetRandomInt(1, 5) == 1)
              {
                PrintHintText(client, "The door is already unlocked!\nPlease wait for it %d seconds.", g_iCountDown);
              }
            }
          }
        }
        bool next_try = TIME_FOR_NEXT_TRY > 0;
        if (next_try)
        {
          HookSingleEntityOutput(Entity, "OnFullyOpen", DL_OutPutOnFullyOpen);
        }
      }
    }
  }
  return Plugin_Continue;
}

public Action TimerDoorCountDown(Handle timer, any Entity)
{
  if (g_iUseCounter > 0)
  {
    if (g_iCountDown > 0)
    {
      if (g_iCountDown < 60)
      {
        EmitSoundToAll("ambient/alarms/klaxon1.wav", Entity, SNDCHAN_AUTO, SNDLEVEL_RAIDSIREN, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_LOW, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
      }
      
      if (g_iCountDown > 30)
      {
        PrintCenterTextAll("[DOOR OPEN] %d sec", g_iCountDown);
      }
      else if (g_iCountDown == 1)
      {
        ControlDoor(Entity, UNLOCK);
      }
      else
      {
        PrintHintTextToAll("[DOOR OPEN] %d sec", g_iCountDown);
      }
      g_iCountDown--;
      return Plugin_Continue;
    }

    if (g_bIsTimerOpen)
    {
      EmitSoundToAll(SoundDoorOpen, Entity);
      g_iSafetyLock = UNLOCK;
      //ControlDoor(Entity, UNLOCK);
      if (FindConVar("hm_mapfinished") != null)
      {
        FindConVar("hm_mapfinished").SetInt(1, false, false);
      }
      
      ServerCommand("sm_weaponscheck");
      
      if (g_bIsAntifarmOn)
      {
        AntiFarmStop();
      }
      
      g_iClock = TIME_TO_DIE - 1;
      g_hTimer = CreateTimer(1.0, NSP_t_Notification, Entity, TIMER_REPEAT);
      
      CreateTimer(10.0, TimerLoadOnEnd1);
      CreateTimer(30.0, TimerLoadOnEnd2);
      
      PrintHintTextToAll("DOOR OPENED");
    }
  }

  return Plugin_Stop;
}

public int ControlDoor(int Entity, int Operation)
{
  if (Operation == LOCK)
  {
    /* Close and lock */
    AcceptEntityInput(Entity, "Close");
    //SetEntPropFloat(Entity, Prop_Data, "m_flSpeed", 3.0);
    AcceptEntityInput(Entity, "ForceClosed");
    AcceptEntityInput(Entity, "Lock");
    SetEntProp(Entity, Prop_Data, "m_hasUnlockSequence", LOCK);
    if (g_IsStandartMap) 
    {
      L4D2_SetEntGlow(Entity, L4D2Glow_Constant, 700, 0, DOOR_LOCKED_COLOR, false);
    }
  }
  else if (Operation == UNLOCK)
  {
    /* Unlock and open */
    SetEntProp(Entity, Prop_Data, "m_hasUnlockSequence", UNLOCK);
    AcceptEntityInput(Entity, "Unlock");
    AcceptEntityInput(Entity, "ForceClosed");
    AcceptEntityInput(Entity, "Open");
    //SetEntPropFloat(Entity, Prop_Data, "m_flSpeed", 200.0);
    if (g_IsStandartMap)
    { 
      L4D2_SetEntGlow(Entity, L4D2Glow_Constant, 700, 0, DOOR_UNLOCKED_COLOR, false);
    }
  }
}

public int DL_OutPutOnFullyOpen(const char[] output, int caller, int activator, float delay)
{
  if (!IsAllOnSafeRoom())
  {
    //SetEntityRenderColor(activator, 255, 0, 0, 255);
    if (g_IsStandartMap) 
    {
      L4D2_SetEntGlow(activator, L4D2Glow_Constant, 700, 0, DOOR_LOCKED_COLOR, false);
    }
    AcceptEntityInput(activator, "Lock");
    SetEntProp(activator, Prop_Data, "m_hasUnlockSequence", 1);
  }
  
  CreateTimer((TIME_FOR_NEXT_TRY + 0.0), DL_t_UnlockSafeRoom, EntIndexToEntRef(activator), TIMER_FLAG_NO_MAPCHANGE);
}

public Action DL_t_UnlockSafeRoom(Handle timer, any entity)
{
  if ((entity = EntRefToEntIndex(entity)) != INVALID_ENT_REFERENCE)
  {
    SetEntProp(entity, Prop_Data, "m_hasUnlockSequence", 0);
    AcceptEntityInput(entity, "Unlock");
    //SetEntityRenderColor(entity, 255, 255, 255, 255);
    if (g_IsStandartMap)
    {
      L4D2_SetEntGlow(entity, L4D2Glow_Constant, 700, 0, DOOR_UNLOCKED_COLOR, false);
    }
  }
}

public void StartTimerAntifarm()
{	
  int realsurvivors = GetSurvivorsCount();
  int good_weapon = CountGoodWeapons();
  int delta;
  if (good_weapon > 12)
  {
    delta = 10 * good_weapon;
  }
  else if (good_weapon > 7)
  {
    delta = 15 * good_weapon;
  }
  else if (good_weapon > 3)
  {
    delta = 20 * good_weapon;
  }
  else
  {
    delta = 0;
  }
  
  if (!g_IsFirstMap)
  {
    // char Message[128];
    if (realsurvivors < 5)
    {
      g_iSecs = 120;
      CreateTimer(1.0, TimerAntiFarmStart, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
      PrintToChatAll("\x04[\x05ANTIFARM\x04]\x01 Antifarm turn after 2 minutes.");
      // PrintToChatAll("\x04[Antifarm]\x01 Антифарм включится после\x05 2-х\x01 минут.");
      // Format(Message, sizeof(Message), "\x04[\x05KEYMAN\x04]\x01 Антифарм 2 минуты, хорошего оружия: \x05%d", good_weapon);
    }
    else
    {
      if (!isFarm())
      {
        g_iSecs = 60;
        CreateTimer(1.0, TimerAntiFarmStart, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
        PrintToChatAll("\x04[\x05ANTIFARM\x04]\x01 Antifarm turn after the first minute");
        // PrintToChatAll("\x04[Antifarm]\x01 Антифарм включится после\x05 1-ой\x01 минуты");
        // Format(Message, sizeof(Message), "\x04[\x05KEYMAN\x04]\x01 Антифарм 2 минуты, хорошего оружия: \x05%d", good_weapon);
      }
      else
      {
        g_iSecs = 240 - delta;
        CreateTimer(1.0, TimerAntiFarmStart, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
        PrintToChatAll("\x04[\x05ANTIFARM\x04]\x01 It will start after \x04%d \x01second(s)", g_iSecs);
        // Format(Message, sizeof(Message), "\x04[\x05KEYMAN\x04]\x01 Антифарм %d секунды, хорошего оружия: \x05%d", g_iSecs, good_weapon);
      }
    }
    // printToRoot(Message);
  }
  else
  {
    if (realsurvivors < 5)
    {
      g_iSecs = 300 - delta;
      CreateTimer(1.0, TimerAntiFarmStart, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
      PrintToChatAll("\x04[\x05ANTIFARM\x04]\x01 It will start after \x04%d \x01second(s)", g_iSecs);
      // PrintToChatAll("\x04[Antifarm]\x01 Антифарм включится после\x05 %d \x01секунд.", g_iSecs);
    }
    else if (realsurvivors > 4 && realsurvivors < 13)
    {
      g_iSecs = 420 - delta;
      CreateTimer(1.0, TimerAntiFarmStart, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
      PrintToChatAll("\x04[\x05ANTIFARM\x04]\x01 It will start after \x04%d \x01second(s)", g_iSecs);
      // PrintToChatAll("\x04[Antifarm]\x01 Антифарм включится после\x05 %d \x01секунд.", g_iSecs);
    }
    else
    {
      g_iSecs = 600 - delta;
      CreateTimer(1.0, TimerAntiFarmStart, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
      PrintToChatAll("\x04[\x05ANTIFARM\x04]\x01 It will start after \x04%d \x01second(s)", g_iSecs);
      // PrintToChatAll("\x04[Antifarm]\x01 Антифарм включится после\x05 %d \x01секунд.", g_iSecs);
    }
  }
}

public void CheckUseCounter()
{
  if (g_iUseCounter == 1)
  {
    if (isFarm())
    {
      VoteOpen();
    }
    else
    {
      CheckWeapons();
      StartTimerAntifarm();
    }
  }
  else if (g_iUseCounter < 400 && ((g_iUseCounter % 60) == 0))
  {
    // char Message[64];
    // Format(Message, sizeof(Message), "\x05UseCounter:\x04 %d", g_iUseCounter);
    // printToRoot(Message);
    SelectKeyman();
  }
  else if (g_iUseCounter == 400)
  {
    SelectKeyman();
    // printToRoot("\x05UseCounter:\x04 400");
    AntiFarmStart();
    g_iSecs = -1;
  }
}

public Action TimerAntiFarmStart(Handle timer)
{
  if (g_iSecs > 0 && g_iUseCounter > 0)
  {
    if (!g_bIsTimerOpen)
    {
      PrintCenterTextAll("[ANTIFARM] %d seconds to start antifarm", g_iSecs);
      // PrintCenterTextAll("[ANTIFARM] %d сек. до антифарма", g_iSecs);
    }
  }
  else if (g_iSecs == 0)
  {
    if (g_iUseCounter > 0)
    {
      if (FindConVar("hm_mapfinished") != null)
      {
        if (!FindConVar("hm_mapfinished").BoolValue)
        {
          AntiFarmStart();
        }
      }
      else
      {
        AntiFarmStart();
      }
    }
  }
  else if (g_iSecs < 0 || g_iUseCounter < 1)
  {
    return Plugin_Stop;
  }
  g_iSecs--;
  
  return Plugin_Continue;
}

public void AntiFarmStart()
{
  g_bIsAntifarmOn = true;
  ServerCommand("sm_cvar monsterbots_on 0");
  ServerCommand("sm_cvar director_no_specials 1");
  CPrintToChatAll("\x04[\x05ANTIFARM\x04]\x05{default} Antifarm is enable, please {blue}end{default} the map.");
  g_iCountDown = sm_ar_DoorLock.IntValue;
  ServerCommand("sm_points_on");		
}

public void AntiFarmStop()
{
  g_bIsAntifarmOn = false;
  ServerCommand("sm_cvar monsterbots_on 1");
  ServerCommand("sm_cvar director_no_specials 0");
  ServerCommand("sm_points_off");	
  // printToRoot("\x04[Antifarm Deactivated]\x05 Антифарм выключен");
}

bool IsTankAlive()
{
  for(int i = 1; i <= MaxClients; i++)
  {
    if (IsClientInGame(i) && IsFakeClient(i))
    {
      if (GetClientZC(i) == ZC_TANK && !IsIncapacitated(i))
      {
        if (IsPlayerAlive(i))
        {
          return true;
        }
      }
    }
  }
  return false;
}

public int GetClientZC(int client)
{
  if (IsValidEntity(client) && IsValidEdict(client)) 
  {
    return GetEntProp(client, Prop_Send, "m_zombieClass");
  }
  return 0;
}

bool IsIncapacitated(int client)
{
  if (GetEntProp(client, Prop_Send, "m_isIncapacitated", 1))
  {
    return true;
  }
  return false;
}

public Action TimerLoadOnEnd1(Handle timer, any client)
{
  if (g_bIsTimerOpen) {
    LoadCFG();
  }
  return Plugin_Stop;
}

public void LoadCFG() {
  ServerCommand("exec hardmod/checkpointreached.cfg");
  EmitSoundToAll(PANIC_SOUND);
  int bot = CreateFakeClient("mob");
  if (bot > 0) {
    if (IsFakeClient(bot)) {
      SpawntyCommand(bot, "z_spawn_old", "mob auto");
      KickClient(bot);
    }
  }
}

public Action TimerLoadOnEnd2(Handle timer, any client) {
  if (g_bIsTimerOpen) {
    Panic();
  }
  return Plugin_Stop;
}

public void Panic() {
  EmitSoundToAll(PANIC_SOUND);
  int bot = CreateFakeClient("mob");
  if (bot > 0) {
    if (IsFakeClient(bot)) {
      SpawntyCommand(bot, "z_spawn_old", "mob auto");
      KickClient(bot);
    }
  }
}

public void SpawntyCommand(int client, char[] sCommand, char[] sArgument) {
  if (client) {
    int iFlags = GetCommandFlags(sCommand);
    SetCommandFlags(sCommand, iFlags & ~FCVAR_CHEAT);
    FakeClientCommand(client, "%s %s", sCommand, sArgument);
    SetCommandFlags(sCommand, iFlags);
  }
}

public void CheckWeapons() {
  int realsurvivors = GetSurvivorsCount();
  if (g_IsFirstMap) {
    if (realsurvivors < 5) {
      g_iCountDown = sm_ar_DoorLock.IntValue;
    }
    else if (realsurvivors > 4 && realsurvivors < 14) {
      if (!isFarm()) {
        g_iCountDown = sm_ar_DoorLock.IntValue;
      } else {
        g_iCountDown = (sm_ar_DoorLock.IntValue + 300);
      }
    } else if (realsurvivors > 13) {
      if (!isFarm()) {
        g_iCountDown = sm_ar_DoorLock.IntValue;
      } else {
        g_iCountDown = (sm_ar_DoorLock.IntValue + 360);
      }
    }
  } else {
    if (realsurvivors < 5) {
      g_iCountDown = sm_ar_DoorLock.IntValue;
    } else {
      if (!isFarm()) {
        g_iCountDown = sm_ar_DoorLock.IntValue;
      } else {
        g_iCountDown = (sm_ar_DoorLock.IntValue + 240);
      }
    }
  }
  if (g_bIsAntifarmOn || FindConVar("l4d2_loot_g_chance_nodrop").IntValue >= 50) {
    g_iCountDown = sm_ar_DoorLock.IntValue;
  }
}
  
public int GetSurvivorsCount() {
  int survivors = 0;
  for(int i = 1; i <= MaxClients;i++) {
    if (IsClientInGame(i)) {	
      if(GetClientTeam(i) == TEAM_SURVIVORS) {
        if(!IsFakeClient(i)) {
          survivors++;
        }
      }
    }
  }
  return survivors;
}

public int CountGoodWeapons() {
  int good_weapon = 0;
  for(int i = 1; i <= MaxClients; i++) {
    if (IsClientInGame(i)){
      if(GetClientTeam(i) == TEAM_SURVIVORS) {
        if(!IsFakeClient(i)) {
          if(IsPlayerAlive(i)) {
            if (HaveGoodWeapon(i)) {
              good_weapon++;
            }
          }
        }
      }
    }
  }
  return good_weapon;
}
  
bool HaveGoodWeapon(int client) {
  char getweapon[32];
  int KidSlot = GetPlayerWeaponSlot(client, 0);
  if (KidSlot != -1) {
    GetEdictClassname(KidSlot, getweapon, 32);
    if (StrEqual(getweapon, "weapon_sniper_scout")) {
      return true;
    } else if (StrEqual(getweapon, "weapon_sniper_awp")) {
      return true;
    } else if (StrEqual(getweapon, "weapon_rifle_ak47")) {
      return true;
    } else if (StrEqual(getweapon, "weapon_grenade_launcher")) {
      return true;
    } else if (StrEqual(getweapon, "weapon_rifle_m60")) {
      return true;
    } else if (StrEqual(getweapon, "weapon_shotgun_spas")) {
      return true;
    }
   }
  return false;
}

bool isFarm()
{
  float percent = 0.0;
  int survivors = GetSurvivorsCount();
  int good_weapon = CountGoodWeapons();

  percent = (100 / survivors * good_weapon) * 1.0;

  if (RoundToNearest(percent) < 33) 
  {
    return true;
  }
  
  return false;
}

public Action Command_CheckWeapons(int client, int args)
{

  if (client)
  {
    int good_weapon = CountGoodWeapons();
    PrintToChat(client, "\x04[\x05KEYMAN\x04]\x01 Good weapons: \x05%d", good_weapon);
  }

  return Plugin_Handled;
}

bool b_StandartMap() {
  return SimpleRegexMatch(MapName, "^c[0-9]{1,2}m[1-9]", PCRE_CASELESS) > 0;
}

public int K_GetEntityRenderColor(int entity)
{
  if (entity > 0)
  {
    int offset = GetEntSendPropOffs(entity, "m_clrRender");
    int r = GetEntData(entity, offset, 1);
    int g = GetEntData(entity, offset+1, 1);
    int b = GetEntData(entity, offset+2, 1);
    char rgb[10];
    Format(rgb, sizeof(rgb), "%d%d%d", r, g, b);
    int color = StringToInt(rgb);
    return color;
  }
  return 0;	
}

public void VoteOpen()
{
  if (!g_bIsTimerOpen)
  {
    g_bIsTimerOpen = true;
  }
  
  if (g_iUseCounter != 1)
  {
    // printToRoot("\x05UseCounter \x04!=\x03 1");
    return;
  }
  
  StartTimerAntifarm();

  PrintToChatAll("\x04[\x05KEYMAN\x04]\x05 What is farm?\x04 It is used to get good weapons before next map");

  g_iYesCount = 0;
  g_iNoCount = 0;
  g_iVoters = 0;
  g_iPlayers = 0;
  g_bAllVoted = false;
  
  for(int i = 1; i <= MaxClients; i++)
  {
    if (IsClientInGame(i) && !IsFakeClient(i))
    {
      g_iVoters++;
      g_iPlayers++;
      ShowVoteMenu(i);
    }
  }

  g_iSeconds = g_hTimout.IntValue;
  
  CreateTimer(g_hTimout.FloatValue + 1.0, Timer_VoteCheck);
  CreateTimer(1.0, TimerInfo, _, TIMER_REPEAT);
  
  return;
}
  
public void ShowVoteMenu(int client)
{
  Menu hMenu = new Menu(MenuVote);
  hMenu.SetTitle("Let's farm?");
  hMenu.AddItem("yes", "Yes, let's farm!");		
  hMenu.AddItem("no", "No"); 
  hMenu.ExitButton = false;
  hMenu.Display(client, g_iSeconds);
}

public int MenuVote(Menu menu, MenuAction action, int param1, int param2)
{
  switch(action)
  {
    case MenuAction_End:
    {
      delete menu;
    }
    case MenuAction_Cancel:
    {
      delete menu;
      //ShowVoteMenu(param1);
    }
    case MenuAction_Select:
    {
      char choice[5]
      menu.GetItem(param2, choice, sizeof(choice));
      
      if (StrEqual(choice, "yes", false))
      {
        g_iYesCount++;
        g_iVoters--;
        ShowResult(param1, true);
      }
      else if (StrEqual(choice, "no", false))
      {
        g_iNoCount++;
        g_iVoters--;
        ShowResult(param1, true);
      }
      
      if (g_iVoters == 0) //Everyone Has Voted
      {
        g_bAllVoted = true;
        g_iSeconds = 0;
        CountVotes();
      }
    }
  }
}

public int ShowResult(int client, bool sound)
{
  if (!g_bAllVoted)
  {
    int g_iVotes = g_iYesCount + g_iNoCount;
    
    if (sound)
    {
      EmitSoundToClient(client, SOUND_VOTE_SELECT);
    }

    if (g_iYesCount >= g_iNoCount)
    {
      PrintHintText(client, "Votes: %d/%d, left %d sec\nYes (%d)\nNo (%d)", g_iVotes, g_iPlayers, g_iSeconds, g_iYesCount, g_iNoCount);
    }
    else
    {
      PrintHintText(client, "Votes: %d/%d, left %d sec\nNo (%d)\nYes (%d)", g_iVotes, g_iPlayers, g_iSeconds, g_iNoCount, g_iYesCount);
    }
  }
}

public Action Timer_VoteCheck(Handle timer)
{
  if (!g_bAllVoted)
  {
    g_bAllVoted = true;
    CountVotes();
  }
}

public Action TimerInfo(Handle timer)
{
  if (g_iSeconds >= 0)
  {
    for(int i = 1; i <= MaxClients; i++)
    {
      if (IsClientInGame(i) && !IsFakeClient(i))
      {
        ShowResult(i, false);
      }	
    }
  }
  else if (g_iSeconds < 0 || g_bAllVoted)
  {
    return Plugin_Stop;
  }

  g_iSeconds--;
  
  return Plugin_Continue;
}

public void CountVotes()
{
  int g_iVotes = g_iYesCount + g_iNoCount;
  int porcent = GetVotesForFarm(g_iYesCount, g_iNoCount);

  if (porcent < 60)
  {
    g_iCountDown = sm_ar_DoorLock.IntValue;
    PrintToChatAll("\x01Players decided \x05not to farm\x01. \x0460%%\x01 vote required \x04(\x01received \x04%d%% \x01of \x04%d \x01votes\x04)", porcent, g_iVotes);
    EmitSoundToAll(SOUND_VOTE_LOSER);
    g_bIsTimerOpen = false;
  }
  else
  {
    PrintToChatAll("\x01Players decided \x05to farm\x01. \x04(\x01received \x04%d%% \x01of \x04%d \x01votes\x04)", porcent, g_iVotes);
    EmitSoundToAll(SOUND_VOTE_WINNER);
    CheckWeapons();
    g_bIsTimerOpen = false;
  }
}

public int GetVotesForFarm(int vote_Yes, int vote_No)
{
  int votes = vote_Yes + vote_No;
  int porcent;
  
  if (votes == 0)
  {
    porcent = 0;
  }
  else
  {
    porcent = RoundToNearest((100 / votes * vote_Yes) * 1.0); 
  }

  return porcent;
}

public Action OnPlayerLeftCheckpoint(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(GetEventInt(event, "userid"));

  if (client && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2)
  {
    g_bInSafeRoom[client] = false;
  }
  
  return Plugin_Continue;
}

public Action OnPlayerEnteredCheckpoint(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(GetEventInt(event, "userid"));
  
  if (client && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == 2)
  {
    g_bInSafeRoom[client] = true;
  }

  return Plugin_Continue;
}

bool IsAllOnSafeRoom()
{
  int PlayersOnSafeRoom = 0;
  int PlayersOut = 0;

  for(int i = 1; i <= MaxClients; i++)
  {
    if (IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i) && IsPlayerAlive(i))
    {
      if (g_bInSafeRoom[i])
      {
        PlayersOnSafeRoom++;
      }
      PlayersOut++;
    }
  }

  return (PlayersOut <= PlayersOnSafeRoom) ? true : false;
}

public Action NSP_t_Notification(Handle timer, any entity)
{
  if (--g_iClock > 0)
  {
    for(int i = 1; i <= MaxClients; i++)
    {
      if (IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i) && IsPlayerAlive(i))
      {
        if (!g_bInSafeRoom[i])
        {
          PrintHintText(i, "Please go inside a safe room or you die!\nTime: %d seconds.", g_iClock);
        }
        else
        {
          PrintHintText(i, "Round ends after: %d seconds.", g_iClock);
        }
      }
    }
    return Plugin_Continue;
  }
  else
  {
    for(int i = 1; i <= MaxClients; i++)
    {
      if (IsClientInGame(i) && GetClientTeam(i) == 2 && !IsFakeClient(i) && IsPlayerAlive(i))
      {
        if (!g_bInSafeRoom[i])
        {
          ForcePlayerSuicide(i);
          PrintHintText(i, "You are not entered in to the save room!");
        }
      }
    }

    if ((entity = EntRefToEntIndex(entity)) != INVALID_ENT_REFERENCE)
    {
      AcceptEntityInput(entity, "Close");
    }
  }

  g_hTimer = null;
  return Plugin_Stop;
}

public void ResetTimer()
{
  g_bIsAntifarmOn = false;
  g_iUseCounter = 0;
  g_bIsTimerOpen = false;
  
  g_iClock = 0;
  g_bTempBlock = false;

  if (g_hTimer)
  {
    KillTimer(g_hTimer);
    g_hTimer = null;
  }
}