import bpy, math
from mathutils import Quaternion, Vector, Matrix
rig = bpy.data.objects["Hero_rig"]
pb = rig.pose.bones
X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
# рукоять за спиной — выше, у плеча рядом с головой
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = rig.data.edit_bones["WeaponBack"]
v = eb.tail - eb.head
eb.head = Vector((0.15, 0.21, 1.55)); eb.tail = eb.head + v
bpy.ops.object.mode_set(mode="POSE")
def aq(b, axis, deg):
    R = pb[b].bone.matrix_local.to_quaternion()
    return R.inverted() @ Quaternion(axis, math.radians(deg)) @ R
def place(b, P):
    rest = pb[b].bone.matrix_local
    pb[b].location = rest.to_3x3().inverted() @ (Vector(P) - rest.translation)
def reset():
    for p in pb:
        p.rotation_quaternion = (1, 0, 0, 0); p.location = (0, 0, 0)
ARM_L = aq("LeftUpperArm", Y, 32); ARM_R = aq("RightUpperArm", Y, -32)
def relaxed():
    pb["LeftUpperArm"].rotation_quaternion = ARM_L
    pb["RightUpperArm"].rotation_quaternion = ARM_R
    pb["LeftLowerArm"].rotation_quaternion = aq("LeftLowerArm", X, -12)
    pb["RightLowerArm"].rotation_quaternion = aq("RightLowerArm", X, -12)
def infl(back, hand, ik):
    pb["Weapon"].constraints["Back"].influence = back
    pb["Weapon"].constraints["Hand"].influence = hand
    pb["LeftLowerArm"].constraints["IK"].influence = ik
def key_all(f):
    for p in pb:
        p.keyframe_insert("rotation_quaternion", frame=f); p.keyframe_insert("location", frame=f)
    for c in ("Back", "Hand"):
        pb["Weapon"].constraints[c].keyframe_insert("influence", frame=f)
    pb["LeftLowerArm"].constraints["IK"].keyframe_insert("influence", frame=f)
def new_action(name):
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    a = bpy.data.actions.new(name); a.use_fake_user = True
    rig.animation_data_create(); rig.animation_data.action = a
    return a
FK_POLE = (0.36, 0.45, 1.12)
# ---------- Idle ----------
new_action("Idle")
for f in (0, 30, 60):
    reset(); relaxed(); infl(1, 0, 0); place("Pole_Arm_L", FK_POLE)
    pb["Chest"].rotation_quaternion = aq("Chest", X, -1.5 if f == 30 else 0)
    key_all(f)
# ---------- Walk ----------
new_action("Walk")
for f in range(0, 33, 2):
    p = 2 * math.pi * f / 32; s, c = math.sin(p), math.cos(p)
    reset(); relaxed(); infl(1, 0, 0); place("Pole_Arm_L", FK_POLE)
    for side, sg in (("Left", 1), ("Right", -1)):
        th = -25 * s * sg
        knee = 5 + 40 * max(0.0, c * sg)
        pb[side + "UpperLeg"].rotation_quaternion = aq(side + "UpperLeg", X, th)
        pb[side + "LowerLeg"].rotation_quaternion = aq(side + "LowerLeg", X, knee)
        pb[side + "Foot"].rotation_quaternion = aq(side + "Foot", X, -(th + knee) * 0.8)
        base = ARM_L if side == "Left" else ARM_R
        pb[side + "UpperArm"].rotation_quaternion = aq(side + "UpperArm", X, 22 * s * sg) @ base
        pb[side + "LowerArm"].rotation_quaternion = aq(side + "LowerArm", X, -12 - 12 * max(0.0, -s * sg))
    pb["Hips"].location = (0, 0.012 - 0.025 * abs(s), 0)
    pb["Hips"].rotation_quaternion = aq("Hips", Z, -6 * s)
    pb["Chest"].rotation_quaternion = aq("Chest", Z, 10 * s)
    key_all(f)
# ---------- Draw / Sheathe ----------
def solve_grab(chest_deg, pole):
    reset(); relaxed(); infl(1, 0, 1); place("Pole_Arm_L", pole)
    pb["Chest"].rotation_quaternion = aq("Chest", Z, chest_deg)
    off = pb["LeftHand"].bone.matrix_local.inverted() @ pb["WeaponHand"].bone.matrix_local
    target = Vector((0.17, 0.17, 1.62))
    for _ in range(8):
        place("IK_Hand_L", target); bpy.context.view_layer.update()
        want = pb["WeaponBack"].matrix @ off.inverted()
        pb["LeftHand"].matrix = Matrix.Translation(pb["LeftHand"].head) @ want.to_3x3().to_4x4()
        bpy.context.view_layer.update()
        target += pb["WeaponBack"].matrix.translation - pb["WeaponHand"].matrix.translation
    err = (pb["WeaponBack"].matrix.translation - pb["WeaponHand"].matrix.translation).length
    return target.copy(), pb["LeftHand"].rotation_quaternion.copy(), err
GRAB_POLE = (0.55, -0.15, 1.55)
g_target, g_rot, g_err = solve_grab(12, GRAB_POLE)
reset(); relaxed(); infl(1, 0, 0); bpy.context.view_layer.update()
wrist0 = pb["LeftHand"].head.copy()
UP = Vector((0.25, 0.0, 1.70)); READY = Vector((0.22, -0.32, 1.08))
ident = Quaternion()
# кадр: (IK-цель, полюс, поворот кисти, наклон груди, back, hand, ik)
D = [
    (0, wrist0, FK_POLE, ident, 0, 1, 0, 0),
    (6, wrist0.lerp(g_target, 0.5) + Vector((0, 0, 0.1)), GRAB_POLE, ident.slerp(g_rot, 0.5), 6, 1, 0, 1),
    (12, g_target, GRAB_POLE, g_rot, 12, 1, 0, 1),
    (15, g_target, GRAB_POLE, g_rot, 12, 1, 1, 1),
    (24, UP, (0.6, 0.0, 1.3), g_rot.slerp(ident, 0.5), 4, 1, 1, 1),
    (32, READY, (0.6, 0.1, 0.8), ident, 0, 1, 1, 1),
    (36, READY, (0.6, 0.1, 0.8), ident, 0, 1, 1, 1),
]
def write(name, frames):
    new_action(name)
    for f, tgt, pole, hrot, chest, back, hand, ik in frames:
        reset(); relaxed(); infl(back, hand, ik)
        place("IK_Hand_L", tgt); place("Pole_Arm_L", pole)
        pb["LeftHand"].rotation_quaternion = hrot
        pb["Chest"].rotation_quaternion = aq("Chest", Z, chest)
        key_all(f)
write("Draw", D)
write("Sheathe", [(36 - k[0],) + k[1:] for k in reversed(D)])
rig.animation_data.action = bpy.data.actions["Idle"]
bpy.context.scene.frame_set(0)
bpy.context.scene.render.fps = 30
result.update(grab_error_m=round(g_err, 4), actions=[a.name for a in bpy.data.actions])
