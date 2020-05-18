#pragma newdecls required


#if SOURCEMOD_V_MINOR < 7
 #error Old version sourcemod!
#endif

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <glow>
#include <regex>
#include <left4dhooks>

int DOOR_LOCKED_COLOR[3] = { 244, 67, 54 };
int DOOR_UNLOCKED_COLOR[3] = { 76, 175, 80 };

// TODO: tarea: TOMAR DE LA VERSIÓN 2.6a el break de la puerta
// transformar codigo a ultima versión

#define FENCE_MODEL01 "models/props_wasteland/exterior_fence003b.mdl"
#define FENCE_MODEL02 "models/props_street/police_barricade.mdl"
#define FENCE_MODEL03 "models/props_street/police_barricade3.mdl"
#define FENCE_MODEL04 "models/props_street/police_barricade4.mdl"
#define FENCE_MODEL05 "models/props_wasteland/exterior_fence001a.mdl"
#define FENCE_MODEL06 "models/props_fortifications/barricade001_128_reference.mdl"
#define FENCE_MODEL07 "models/props_wasteland/exterior_fence_notbarbed002c.mdl"
#define FENCE_MODEL08 "models/props_wasteland/exterior_fence_notbarbed002b.mdl"
#define FENCE_MODEL09 "models/props_wasteland/exterior_fence_notbarbed002d.mdl"
#define FENCE_MODEL10 "models/props_wasteland/exterior_fence_notbarbed002f.mdl"
#define FENCE_MODEL11 "models/props_wasteland/exterior_fence_notbarbed002e.mdl"
#define FENCE_MODEL12 "models/props_urban/fence_cover001_256.mdl"
#define FENCE_MODEL13 "models/props_exteriors/roadsidefence_512.mdl"
#define FENCE_MODEL14 "models/props_exteriors/roadsidefence_64.mdl"
#define FENCE_MODEL15 "models/props_urban/fence_cover001_128.mdl"


int OFFSET_LOCKED,
SaferoomDoor,
g_iCooldown,
g_iRoundCounter,
clientTimeout[66];

bool g_bLocked,
g_bTempBlock,
gbFirstItemPickedUp,
isClientLoading[66];

ConVar cvarLockRoundOne,
cvarLockRoundTwo,
cvarLockGlowRange,
cvarLockHintText,
cvarLockNotify,
cvarClientTimeOut,
g_hStopbots;
GlobalForward g_IsCheckpointDoorOpened;

char g_CurrentMap[64];

public Plugin myinfo = {
 name = "[l4d2] Door lock",
 author = "Aleexxx",
 description = "Door lock control",
 version = "1.0.0",
 url = "https://draen.org"
};

public void OnPluginStart() {

  OFFSET_LOCKED = FindSendPropInfo("CPropDoorRotatingCheckpoint", "m_bLocked");
  RegAdminCmd("sm_lock", CmdLock, ADMFLAG_ROOT, "lock the door");
  RegAdminCmd("sm_unlock", CmdUnLock, ADMFLAG_ROOT, "unlock the door");
  g_IsCheckpointDoorOpened = new GlobalForward("Lock_CheckpointDoorStartOpened", ET_Ignore);
  HookEvent("player_left_checkpoint", Event_LeftSaferoom, EventHookMode_Pre);
  HookEvent("player_team", Event_Join_Team, EventHookMode_Pre);
  HookEvent("round_start", Event_RoundStart, EventHookMode_Pre);
  HookEvent("round_end", Event_RoundEnd, EventHookMode_Pre);
  HookEvent("door_unlocked", Event_DoorUnlocked, EventHookMode_Pre);
  HookEvent("item_pickup", Event_RoundStartAndItemPickup, EventHookMode_Pre);
  cvarLockRoundOne = CreateConVar("l4d2_lock_roundone", "40", "How long the door is locked on round 1 - this round takes longer to load. (Default: 40)");
  cvarLockRoundTwo = CreateConVar("l4d2_lock_roundtwo", "30", "How long the door is locked on round two. (Default: 30)");
  cvarLockGlowRange = CreateConVar("l4d2_lock_glowrange", "800", "How far the glow ranges off of the saferoom door. (Default: 800)");
  cvarLockHintText = CreateConVar("l4d2_lock_hinttext", "0", "Does the plugin print the countdown in center screen? (Default: 0)");
  cvarLockNotify = CreateConVar("l4d2_lock_notify", "10", "What time to notify the players about the door going to open. (Default: 10)");
  cvarClientTimeOut = CreateConVar("l4d2_lock_timeout", "30", "Seconds will wait after a map starts waiting for players. (Default: 30)");
  g_hStopbots = FindConVar("sb_move");

  ClearVariables();
}

public void OnMapStart() {
  if (!IsModelPrecached(FENCE_MODEL01)) {
    PrecacheModel(FENCE_MODEL01, true);
  }
  if (!IsModelPrecached(FENCE_MODEL02)) {
    PrecacheModel(FENCE_MODEL02, true);
  }
  if (!IsModelPrecached(FENCE_MODEL03)) {
    PrecacheModel(FENCE_MODEL03, true);
  }
  if (!IsModelPrecached(FENCE_MODEL04)) {
    PrecacheModel(FENCE_MODEL04, true);
  }
  if (!IsModelPrecached(FENCE_MODEL05)) {
    PrecacheModel(FENCE_MODEL05, true);
  }
  if (!IsModelPrecached(FENCE_MODEL06)) {
    PrecacheModel(FENCE_MODEL06, true);
  }
  if (!IsModelPrecached(FENCE_MODEL07)) {
    PrecacheModel(FENCE_MODEL07, true);
  }
  if (!IsModelPrecached(FENCE_MODEL08)) {
    PrecacheModel(FENCE_MODEL08, true);
  }
  if (!IsModelPrecached(FENCE_MODEL09)) {
    PrecacheModel(FENCE_MODEL09, true);
  }
  if (!IsModelPrecached(FENCE_MODEL10)) {
    PrecacheModel(FENCE_MODEL10, true);
  }
  if (!IsModelPrecached(FENCE_MODEL11)) {
    PrecacheModel(FENCE_MODEL11, true);
  }
  if (!IsModelPrecached(FENCE_MODEL12)) {
    PrecacheModel(FENCE_MODEL12, true);
  }
  if (!IsModelPrecached(FENCE_MODEL13)) {
    PrecacheModel(FENCE_MODEL13, true);
  }
  if (!IsModelPrecached(FENCE_MODEL14)) {
    PrecacheModel(FENCE_MODEL14, true);
  }
  if (!IsModelPrecached(FENCE_MODEL15)) {
    PrecacheModel(FENCE_MODEL15, true);
  }

  GetCurrentMap(g_CurrentMap, sizeof(g_CurrentMap));
  g_iRoundCounter = 1;
  ClearVariables();
}

stock void CheatCommand(int client = 0, char[] command, char[] arguments = "") {
  if (!client || !IsClientInGame(client)) {
    for (int target = 1; target <= MaxClients; target++) {
      if (IsClientInGame(target)) {
        client = target;
        break;
      }
    }
    if (!client || !IsClientInGame(client)) {
      return;
    }
  }

  int flags = GetCommandFlags(command);
  SetCommandFlags(command, flags & ~FCVAR_CHEAT);
  FakeClientCommand(client, "%s %s", command, arguments);
  SetCommandFlags(command, flags);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
  ClearVariables();
  gbFirstItemPickedUp = false;
  g_bLocked = true;
  g_bTempBlock = false;
}

public Action Event_RoundStartAndItemPickup(Event event, const char[] name, bool dontBroadcast) {
  if (!gbFirstItemPickedUp) {
    gbFirstItemPickedUp = true;
    CreateTimer(0.2, PluginStartSequence01);
  }
  if (!g_bTempBlock) {
    g_bTempBlock = true;
    CreateTimer(1.0, LockSafeRoom);
  }
}


void StopBots() {
  // g_hStopbots.SetString("0");
}

void StartBots() {
  // g_hStopbots.SetString("1");
}

public Action LockSafeRoom(Handle timer) {

  if (!L4D_IsFirstMapInScenario()) {

    char current_map[56];
    GetCurrentMap(current_map, sizeof(current_map));
    if (StrEqual(current_map, "c10m5_houseboat", false)) {
      SaferoomDoor = Now_FindAndLockSaferoomDoor();
    } else {
      float vSurvivor[3];
      float vDoor[3];

      for (int i = 1; i <= MaxClients; i++) {

        if (IsClientInGame(i) && GetClientTeam(i) == 2) {
          GetClientAbsOrigin(i, vSurvivor);

          if (vSurvivor[0] != 0 && vSurvivor[1] != 0 && vSurvivor[2] != 0) {
            int iEnt = -1;
            while ((iEnt = FindEntityByClassname(iEnt, "prop_door_rotating_checkpoint")) != -1) {
              if (! (GetEntProp(iEnt, Prop_Data, "m_spawnflags") == 32768)) {
                GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vDoor);
                if (! (GetVectorDistance(vSurvivor, vDoor, false) > 1000)) {
                  DispatchKeyValue(iEnt, "spawnflags", "32768");
                  if (b_StandartMap()) {
                    L4D2_SetEntGlow(iEnt, L4D2Glow_OnLookAt, cvarLockGlowRange.IntValue, 0, DOOR_LOCKED_COLOR, false);
                    SetEntityRenderColor(iEnt, 0, 0, 0, 255);
                  }
                  HookSingleEntityOutput(iEnt, "OnFullyOpen", OnStartDoorFullyOpened, true);
                  SaferoomDoor = iEnt;
                }
              }
            }
          }
        }
      }
      int iEnt = -1;
      while ((iEnt = FindEntityByClassname(iEnt, "prop_door_rotating_checkpoint")) != -1) {
        if (! (GetEntProp(iEnt, Prop_Data, "m_spawnflags") == 32768)) {
          GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vDoor);
          if (! (GetVectorDistance(vSurvivor, vDoor, false) > 1000)) {
            DispatchKeyValue(iEnt, "spawnflags", "32768");
            if (b_StandartMap()) {
              L4D2_SetEntGlow(iEnt, L4D2Glow_OnLookAt, cvarLockGlowRange.IntValue, 0, DOOR_LOCKED_COLOR, false);
              SetEntityRenderColor(iEnt, 0, 0, 0, 255);
            }
            HookSingleEntityOutput(iEnt, "OnFullyOpen", OnStartDoorFullyOpened, true);
            SaferoomDoor = iEnt;
          }
        }
      }
    }

  } else {
    BlockPath();
  }

  return Plugin_Continue;
}


public Action PluginStartSequence01(Handle timer) {
  for (int i = 1; i <= MaxClients; i++) {

    isClientLoading[i] = true;
    clientTimeout[i] = 0;

  }
  CreateTimer(0.2, PluginStartSequence02);
  return Plugin_Continue;
}

stock int Now_FindAndLockSaferoomDoor() {
  int ent = -1;
  while ((ent = FindEntityByClassnameEx(ent, "prop_door_rotating_checkpoint")) != -1) {
    if (IsValidEntity(ent)) {
      if (GetEntData(ent, OFFSET_LOCKED, 1)) {
        DispatchKeyValue(ent, "spawnflags", "32768");
        if (b_StandartMap()) {
          L4D2_SetEntGlow(ent, L4D2Glow_OnLookAt, cvarLockGlowRange.IntValue, 0, DOOR_UNLOCKED_COLOR, false);
          SetEntityRenderColor(ent, 0, 0, 0, 255);
        }
        HookSingleEntityOutput(ent, "OnFullyOpen", OnStartDoorFullyOpened, true);
        return ent;
      }
    }
  }

  return ent;
}

stock int FindEntityByClassnameEx(int startEnt, const char[] classname) {
  while (startEnt > -1 && !IsValidEntity(startEnt)) {
    startEnt--;
  }
  return FindEntityByClassname(startEnt, classname);
}

stock void Now_UnlockSaferoomDoor() {

  if (SaferoomDoor > 0 && IsValidEntity(SaferoomDoor)) {
    DispatchKeyValue(SaferoomDoor, "spawnflags", "8192");
    if (b_StandartMap()) {
      L4D2_SetEntGlow(SaferoomDoor, L4D2Glow_OnLookAt, cvarLockGlowRange.IntValue, 0, DOOR_UNLOCKED_COLOR, false);
      SetEntityRenderColor(SaferoomDoor, 0, 0, 0, 255);
    }
  }
  Call_StartForward(g_IsCheckpointDoorOpened);
  Call_Finish();
}

public Action PluginStartSequence02(Handle timer) {
  CreateTimer(1.0, LoadingTimer);
}

public Action LoadingTimer(Handle timer) {

  CreateTimer(1.0, timerLockSwitch, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

}

public Action Event_LeftSaferoom(Event event, const char[] name, bool dontBroadcast) {
  g_bLocked = false;
}

public Action Event_DoorUnlocked(Event event, const char[] name, bool dontBroadcast) {
  if (g_bLocked == true) {
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (!IsFakeClient(client) && IsClientInGame(client)) {
      PrintCenterText(client, "Door will open: %i seconds", g_iCooldown);
    }
  }
  return Plugin_Handled;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
  g_iRoundCounter = 2;
  ClearVariables();
  return Plugin_Continue;
}

public Action CmdLock(int client, int args) {
  char class[128];
  int i = MaxClients + 1;
  while (i <= 2048) {
    if (IsValidEntity(i)) {
      GetEdictClassname(i, class, sizeof(class));
      if (StrEqual(class, "prop_door_rotating_checkpoint", true)) {
        AcceptEntityInput(i, "Close");
        AcceptEntityInput(i, "Lock");
        SetVariantString("spawnflags 40960");
        AcceptEntityInput(i, "AddOutput");
        if (b_StandartMap()) {
          L4D2_SetEntGlow(i, L4D2Glow_OnLookAt, cvarLockGlowRange.IntValue, 0, DOOR_LOCKED_COLOR, false);
          SetEntityRenderColor(i, 0, 0, 0, 255);
        }
      }
    }
    i++;
  }
  PrintToChat(client, "\x04[\x05DOORLOCK\x04]\x01 Saferoom doors are locked!");
  return Plugin_Handled;
}

stock void BlockPath() {
  float fnOrigin[3],
  fnAngles[3];
  int fence = CreateEntityByName("prop_dynamic_override");
  int red = GetRandomInt(0, 255);
  int green = GetRandomInt(0, 255);
  int blue = GetRandomInt(0, 255);
  SetEntityRenderColor(fence, red, green, blue, 255);
  if (StrEqual(g_CurrentMap, "c1m1_hotel")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL01);
    fnOrigin[0] = 392.003998;
    fnAngles[0] = 0.409058;
    fnOrigin[1] = 5635.555176;
    fnAngles[1] = 178.616119;
    fnOrigin[2] = 2925.031250;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c2m1_highway")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL04);
    fnOrigin[0] = 10003.427734;
    fnAngles[0] = 6.784813;
    fnOrigin[1] = 7790.717285;
    fnAngles[1] = -179.112259;
    fnOrigin[2] = -516.365295;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c3m1_plankcountry")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL06);
    fnOrigin[0] = -12486.348633;
    fnAngles[0] = 1.611764;
    fnOrigin[1] = 10438.381836;
    fnAngles[1] = -27.414877;
    fnOrigin[2] = 244.893372;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c4m1_milltown_a")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL06);
    fnOrigin[0] = -6358.857422;
    fnAngles[0] = 1.356968;
    fnOrigin[1] = 7455.994141;
    fnAngles[1] = 180.000000;
    fnOrigin[2] = 95.031250;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c5m1_waterfront")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL15);
    fnOrigin[0] = 604.000000;
    fnOrigin[1] = -28.000000;
    fnOrigin[2] = -377.000000;
    fnAngles[0] = 0.000000;
    fnAngles[1] = 175.000000;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c6m1_riverbank")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL04);
    fnOrigin[0] = 916.505737;
    fnAngles[0] = 0.135685;
    fnOrigin[1] = 3674.522705;
    fnAngles[1] = -89.859390;
    fnOrigin[2] = 93.659073;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c7m1_docks")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL04);
    fnOrigin[0] = 13365.058594;
    fnAngles[0] = 0.000000;
    fnOrigin[1] = 2152.831299;
    fnAngles[1] = -178.208420;
    fnOrigin[2] = -94.121269;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c8m1_apartment") || StrEqual(g_CurrentMap, "l4d2_hospital01_apartment")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL02);
    fnOrigin[0] = 1786.985718;
    fnAngles[0] = -1.221282;
    fnOrigin[1] = 1144.813354;
    fnAngles[1] = -0.271370;
    fnOrigin[2] = 432.031250;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c9m1_alleys")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL04);
    fnOrigin[0] = -9067.495117;
    fnAngles[0] = -2.968737;
    fnOrigin[1] = -9684.145508;
    fnAngles[1] = -92.191689;
    fnOrigin[2] = -2.509978;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c11m1_greenhouse")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL08);
    fnOrigin[0] = 6384.835449;
    fnAngles[0] = 0.000000;
    fnOrigin[1] = -437.813385;
    fnAngles[1] = 180.000000;
    fnOrigin[2] = 725.031250;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c12m1_hilltop") || StrEqual(g_CurrentMap, "C12m1_hilltop")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL13);
    fnOrigin[0] = -8113.000000;
    fnAngles[0] = 0.000000;
    fnOrigin[1] = -15017.000000;
    fnAngles[1] = 161.000000;
    fnOrigin[2] = 278.000000;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c13m1_alpinecreek") || StrEqual(g_CurrentMap, "c13m1_alpinecreek_night")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL04);
    fnOrigin[0] = -2982.207275;
    fnAngles[0] = 4.749351;
    fnOrigin[1] = -404.366333;
    fnAngles[1] = 92.358307;
    fnOrigin[2] = 78.559059;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "l4d2_orange01_city")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL03);

    fnOrigin[0] = -2539.044189;
    fnAngles[0] = -0.306694;
    fnOrigin[1] = -3554.748047;
    fnAngles[1] = -0.295615;
    fnOrigin[2] = 512.031250;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "l4d2_city17_01")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL12);

    fnOrigin[0] = 3776.000000;
    fnAngles[0] = 0.000000;
    fnOrigin[1] = -5044.000000;
    fnAngles[1] = 89.000000;
    fnOrigin[2] = -120.000000;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "bwm1_climb")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL06);

    fnOrigin[0] = -522.000000;
    fnAngles[0] = 0.000000;
    fnOrigin[1] = 702.000000;
    fnAngles[1] = 179.000000;
    fnOrigin[2] = 0.000000;
    fnAngles[2] = 0.000000;
  }
  SetEntProp(fence, Prop_Send, "m_nSolidType", 6);
  DispatchKeyValue(fence, "targetname", "anti-rush-system-fence");
  DispatchSpawn(fence);
  TeleportEntity(fence, fnOrigin, fnAngles, NULL_VECTOR);

  float fn2Origin[3],
  fn2Angles[3];
  int fence2 = CreateEntityByName("prop_dynamic_override");
  if (StrEqual(g_CurrentMap, "c2m1_highway")) {
    DispatchKeyValue(fence2, "model", FENCE_MODEL04);

    fn2Origin[0] = 10003.427734;
    fn2Angles[0] = 6.784813;
    fn2Origin[1] = 8351.467773;
    fn2Angles[1] = -179.112259;
    fn2Origin[2] = -515.465454;
    fn2Angles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c4m1_milltown_a")) {
    DispatchKeyValue(fence2, "model", FENCE_MODEL04);

    fn2Origin[0] = -6362.469727;
    fn2Angles[0] = 1.476095;
    fn2Origin[1] = 7397.324707;
    fn2Angles[1] = 180.000000;
    fn2Origin[2] = 306.031250;
    fn2Angles[2] = 0.000000;
  }
  // else if (StrEqual(g_CurrentMap, "c8m1_apartment") || StrEqual(g_CurrentMap, "l4d2_hospital01_apartment")) {
  //   DispatchKeyValue(fence2, "model", FENCE_MODEL15);
  //   // "origin" "2219 926 416"
	//   // "angles" "90 199 7"
  //   fn2Origin[0] = 2219.000000;
  //   fn2Origin[1] = 926.000000;
  //   fn2Origin[2] = 416.024597;
  //   fn2Angles[0] = 90.000000;
  //   fn2Angles[1] = -180.000000;
  //   fn2Angles[2] = 0.000000;
  // }
  else if (StrEqual(g_CurrentMap, "c9m1_alleys")) {
    DispatchKeyValue(fence2, "model", FENCE_MODEL04);

    fn2Origin[0] = -9617.561523;
    fn2Angles[0] = -0.119123;
    fn2Origin[1] = -9659.479492;
    fn2Angles[1] = -90.020599;
    fn2Origin[2] = -2.663688;
    fn2Angles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c11m1_greenhouse")) {
    DispatchKeyValue(fence2, "model", FENCE_MODEL09);

    fn2Origin[0] = 6280.875000;
    fn2Angles[0] = 0.000000;
    fn2Origin[1] = -786.662415;
    fn2Angles[1] = 180.000000;
    fn2Origin[2] = 925.031250;
    fn2Angles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c12m1_hilltop") || StrEqual(g_CurrentMap, "C12m1_hilltop")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL14);

    fnOrigin[0] = -8202.000000;
    fnAngles[0] = 0.000000;
    fnOrigin[1] = -15289.000000;
    fnAngles[1] = 161.000000;
    fnOrigin[2] = 333.000000;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "l4d2_city17_01")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL12);

    fnOrigin[0] = 4015.000000;
    fnAngles[0] = 0.000000;
    fnOrigin[1] = -5022.000000;
    fnAngles[1] = 93.000000;
    fnOrigin[2] = -124.000000;
    fnAngles[2] = 0.000000;
  }
  SetEntProp(fence2, Prop_Send, "m_nSolidType", 6);
  DispatchKeyValue(fence2, "targetname", "anti-rush-system-fence");
  DispatchSpawn(fence2);
  TeleportEntity(fence2, fn2Origin, fn2Angles, NULL_VECTOR);

  float fn3Origin[3],
  fn3Angles[3];
  int fence3 = CreateEntityByName("prop_dynamic_override");
  if (StrEqual(g_CurrentMap, "c4m1_milltown_a")) {
    DispatchKeyValue(fence3, "model", FENCE_MODEL03);

    fn3Origin[0] = -6366.153320;
    fn3Angles[0] = 2.018882;
    fn3Origin[1] = 6976.294922;
    fn3Angles[1] = -1.210750;
    fn3Origin[2] = 232.031265;
    fn3Angles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c9m1_alleys")) {
    DispatchKeyValue(fence3, "model", FENCE_MODEL04);

    fn3Origin[0] = -10102.182617;
    fn3Angles[0] = 1.237835;
    fn3Origin[1] = -9660.498047;
    fn3Angles[1] = -90.156395;
    fn3Origin[2] = -5.845541;
    fn3Angles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c11m1_greenhouse")) {
    DispatchKeyValue(fence3, "model", FENCE_MODEL11);

    fn3Origin[0] = 6280.875000;
    fn3Angles[0] = 0.000000;
    fn3Origin[1] = -536.662415;
    fn3Angles[1] = 180.000000;
    fn3Origin[2] = 925.031250;
    fn3Angles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "c12m1_hilltop") || StrEqual(g_CurrentMap, "C12m1_hilltop")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL14);

    fnOrigin[0] = -8192.000000;
    fnAngles[0] = 0.000000;
    fnOrigin[1] = -15236.000000;
    fnAngles[1] = 161.000000;
    fnOrigin[2] = 382.000000;
    fnAngles[2] = 0.000000;
  } else if (StrEqual(g_CurrentMap, "l4d2_city17_01")) {
    DispatchKeyValue(fence, "model", FENCE_MODEL12);

    fnOrigin[0] = 4218.000000;
    fnAngles[0] = 0.000000;
    fnOrigin[1] = -5016.000000;
    fnAngles[1] = -93.000000;
    fnOrigin[2] = -124.000000;
    fnAngles[2] = 0.000000;
  }
  SetEntProp(fence3, Prop_Send, "m_nSolidType", 6);
  DispatchKeyValue(fence3, "targetname", "anti-rush-system-fence");
  DispatchSpawn(fence3);
  TeleportEntity(fence3, fn3Origin, fn3Angles, NULL_VECTOR);

  g_bLocked = true;
  StopBots();

}

stock void UnblockPath() {
  CheatCommand(_, "ent_fire", "anti-rush-system-fence KillHierarchy");
  g_bLocked = false;
  StartBots();
}

public Action CmdUnLock(int client, int args) {
  char class[128];
  int i = MaxClients + 1;
  while (i <= 2048) {
    if (IsValidEntity(i)) {
      GetEdictClassname(i, class, sizeof(class));
      if (StrEqual(class, "prop_door_rotating_checkpoint", true)) {
        SetVariantString("spawnflags 8192");
        AcceptEntityInput(i, "AddOutput");
        AcceptEntityInput(i, "Unlock");
        AcceptEntityInput(i, "Open");
        if (b_StandartMap()) {
          L4D2_SetEntGlow(i, L4D2Glow_OnLookAt, 1000, cvarLockGlowRange.IntValue, DOOR_UNLOCKED_COLOR, false);
          SetEntityRenderColor(i, 0, 0, 0, 255);
        }
      }
    }
    i++;
  }
  PrintToChat(client, "\x04[\x05DOORLOCK\x04]\x01 Saferoom doors are unlocked!");
  return Plugin_Handled;
}

public Action timerLockSwitch(Handle timer) {
  if (isFinishedLoading()) {

    if (!L4D_IsFirstMapInScenario()) {

      if (g_iCooldown > 0) {
        g_bLocked = true;
      } else {
        if (g_iCooldown) {
          if (g_iCooldown < 0 || g_bLocked) {
            return Plugin_Stop;
          }
        }

        Now_UnlockSaferoomDoor();
        g_bLocked = false;
        PrintToChatAll("\x04[\x05DOORLOCK\x04]\x01 Saferoom doors are open!");

        if (cvarLockHintText.IntValue == 1) {
          PrintHintTextToAll("The saferoom doors are open!");
        }
      }
      if (cvarLockHintText.IntValue == 1) {
        if (g_iCooldown > 0) {
          PrintHintTextToAll("%i second(s) till the saferoom doors open!", g_iCooldown);
        }
      }

      if (cvarLockHintText.IntValue != 1 && g_iCooldown <= cvarLockNotify.IntValue && g_iCooldown > 0) {
        for (int i = 1; i <= MaxClients; i++) {
          if (IsClientInGame(i) && (GetClientTeam(i) == 2)) PrintCenterText(i, "Door will open in: %i seconds! Please wait.", g_iCooldown);
        }
      }

      g_iCooldown -= 1;

    } else {
      if (g_iCooldown > 0) {
        g_bLocked = true;
      } else {
        if (g_iCooldown) {

          if (g_iCooldown < 0 || g_bLocked) {

            return Plugin_Stop;
          }
        }

        UnblockPath();
        g_bLocked = false;
        PrintToChatAll("\x04[\x05DOORLOCK\x04]\x01 Let's rock!");
      }
      if (cvarLockHintText.IntValue == 1) {
        if (g_iCooldown > 0) {
          PrintHintTextToAll("Please wait: %is", g_iCooldown);
        }
      }

      if (cvarLockHintText.IntValue != 1 && g_iCooldown <= cvarLockNotify.IntValue && g_iCooldown > 0) {
        for (int i = 1; i <= MaxClients; i++) {
          if (IsClientInGame(i) && (GetClientTeam(i) == 2)) PrintCenterText(i, "Please wait: %is", g_iCooldown);
        }
      }

      g_iCooldown -= 1;
    }

  }
  return Plugin_Continue;
}

public void OnStartDoorFullyOpened(const char[] output, int caller, int activator, float delay) {
  AcceptEntityInput(activator, "Lock");
  SetEntProp(activator, Prop_Data, "m_hasUnlockSequence", 1);
}

stock void ClearVariables() {
  if (g_iRoundCounter == 1) {
    g_iCooldown = cvarLockRoundOne.IntValue;
  } else {
    if (g_iRoundCounter == 2) {
      g_iCooldown = cvarLockRoundTwo.IntValue;
    }
  }
}

bool b_StandartMap() {
  return SimpleRegexMatch(g_CurrentMap, "^c[0-9]{1,2}m[1-9]", PCRE_CASELESS) > 0;
}

public void OnClientDisconnect(int client) {
  isClientLoading[client] = false;
  clientTimeout[client] = 0;
}

public Action Event_Join_Team(Event event, const char[] event_name, bool dontBroadcast) {
  int client = GetClientOfUserId(event.GetInt("userid"));
  if (isClientValid(client)) {
    isClientLoading[client] = false;
    clientTimeout[client] = 0;
  }
}


bool isFinishedLoading() {
  for (int i = 1; i <= MaxClients; i++) {

    if (IsClientConnected(i)) {

      if (!IsClientInGame(i) && !IsFakeClient(i)) {
        clientTimeout[i]++;

        if (isClientLoading[i] && clientTimeout[i] == 1) {

          for (int e = 1; e <= MaxClients; e++) {
            if (IsClientInGame(e) && (GetClientTeam(e) == 2) && e != i) PrintCenterText(e, "Waiting for %N to join the game", i);
          }

          isClientLoading[i] = true;
        } else if (clientTimeout[i] == cvarClientTimeOut.IntValue) {
          /* Handling clients timing out */
          for (int e = 1; e <= MaxClients; e++) {
            if (IsClientInGame(e) && (GetClientTeam(e) == 2) && e != i) PrintCenterText(e, "We will no longer wait for %N (timeout)", i);
          }

          isClientLoading[i] = false;
        }

      } else {

        isClientLoading[i] = false;
      }
    } else isClientLoading[i] = false;
  }

  return ! IsAnyClientLoading();
}


bool IsAnyClientLoading() {
  for (int i = 1; i <= MaxClients; i++) {
    if (isClientLoading[i]) {
      return true;
    }
  }
  return false;
}

bool isClientValid(int client) {
  if (client <= 0) {
    return false;
  }
  if (!IsClientConnected(client)) {
    return false;
  }
  if (!IsClientInGame(client)) {
    return false;
  }
  if (IsFakeClient(client)) {
    return false;
  }
  return true;
}