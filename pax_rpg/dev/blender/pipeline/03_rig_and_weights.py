import bpy
from mathutils import Vector, Matrix
sw = bpy.data.objects["Sword"]
if "home" in sw:
    sw.location = Vector(sw["home"])
body = bpy.data.objects["Hero_male"]
coll = body.users_collection[0]
old = bpy.data.objects.get("Hero_rig")
if old:
    bpy.data.objects.remove(old, do_unlink=True)
arm = bpy.data.armatures.new("Hero_rig")
rig = bpy.data.objects.new("Hero_rig", arm)
coll.objects.link(rig)
bpy.context.view_layer.objects.active = rig
for o in bpy.context.selected_objects:
    o.select_set(False)
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
E = arm.edit_bones
def bone(name, h, t, parent=None, deform=True, connect=False, roll_z=None):
    b = E.new(name); b.head = Vector(h); b.tail = Vector(t)
    if parent: b.parent = E[parent]; b.use_connect = connect
    b.use_deform = deform
    if roll_z is not None: b.align_roll(Vector(roll_z))
    return b
FWD = (0, -1, 0)   # персонаж смотрит в -Y
bone("Root", (0, 0, 0), (0, 0, 0.2), deform=False)
bone("Hips", (0, 0.02, 0.95), (0, 0.02, 1.05), "Root", roll_z=FWD)
bone("Spine", (0, 0.02, 1.05), (0, 0.02, 1.15), "Hips", connect=True, roll_z=FWD)
bone("Chest", (0, 0.02, 1.15), (0, 0.02, 1.25), "Spine", connect=True, roll_z=FWD)
bone("UpperChest", (0, 0.02, 1.25), (0, 0.03, 1.36), "Chest", connect=True, roll_z=FWD)
bone("Neck", (0, 0.03, 1.36), (0, 0.03, 1.47), "UpperChest", connect=True, roll_z=FWD)
bone("Head", (0, 0.03, 1.47), (0, 0.03, 1.72), "Neck", connect=True, roll_z=FWD)
for side, s in (("Left", 1), ("Right", -1)):
    bone(side + "Shoulder", (0.03 * s, 0.03, 1.33), (0.16 * s, 0.04, 1.31), "UpperChest", roll_z=FWD)
    bone(side + "UpperArm", (0.16 * s, 0.04, 1.31), (0.30 * s, 0.06, 1.12), side + "Shoulder", connect=True, roll_z=FWD)
    bone(side + "LowerArm", (0.30 * s, 0.06, 1.12), (0.42 * s, 0.05, 0.96), side + "UpperArm", connect=True, roll_z=FWD)
    bone(side + "Hand", (0.42 * s, 0.05, 0.96), (0.47 * s, 0.04, 0.80), side + "LowerArm", connect=True, roll_z=FWD)
    bone(side + "UpperLeg", (0.10 * s, 0.02, 0.93), (0.15 * s, 0.01, 0.50), "Hips", roll_z=FWD)
    bone(side + "LowerLeg", (0.15 * s, 0.01, 0.50), (0.195 * s, 0.05, 0.09), side + "UpperLeg", connect=True, roll_z=FWD)
    bone(side + "Foot", (0.195 * s, 0.05, 0.09), (0.195 * s, -0.07, 0.02), side + "LowerLeg", connect=True, roll_z=(0, 0, 1))
    bone(side + "Toes", (0.195 * s, -0.07, 0.02), (0.195 * s, -0.13, 0.02), side + "Foot", connect=True, roll_z=(0, 0, 1))
# меч: ось из отделения (к навершию), кончик — в обратную сторону
d = Vector((0.163, 0.077, 0.984)).normalized()
grip = Vector(sw.location)
tip_dir = -d
x0 = (Vector((1, 0, 0)) - tip_dir * tip_dir.x).normalized()
z0 = x0.cross(tip_dir)
bone("Weapon", grip, grip + tip_dir * 0.3, "Root", roll_z=z0)
bone("WeaponHand", grip, grip + tip_dir * 0.3, "LeftHand", deform=False, roll_z=z0)
# за спиной: рукоять у левого плеча, клинок вниз к правому бедру
back_grip = Vector((0.13, 0.21, 1.42))
t = Vector((-0.45, 0.0, -0.89)).normalized()
x1 = (Vector((1, 0, 0)) - t * t.x).normalized()
z1 = x1.cross(t)
bone("WeaponBack", back_grip, back_grip + t * 0.3, "UpperChest", deform=False, roll_z=z1)
# IK левой руки: цель и полюс (локоть назад)
bone("IK_Hand_L", (0.42, 0.05, 0.96), (0.42, 0.05, 0.86), "Root", deform=False)
bone("Pole_Arm_L", (0.36, 0.45, 1.12), (0.36, 0.45, 1.02), "Root", deform=False)
bpy.ops.object.mode_set(mode="POSE")
pb = rig.pose.bones
ik = pb["LeftLowerArm"].constraints.new("IK")
ik.name = "IK"; ik.target = rig; ik.subtarget = "IK_Hand_L"; ik.pole_target = rig; ik.pole_subtarget = "Pole_Arm_L"
ik.pole_angle = -1.5708; ik.chain_count = 2; ik.influence = 0.0
for name, tgt, infl in (("Back", "WeaponBack", 1.0), ("Hand", "WeaponHand", 0.0)):
    c = pb["Weapon"].constraints.new("COPY_TRANSFORMS"); c.name = name
    c.target = rig; c.subtarget = tgt; c.influence = infl
for p in pb:
    p.rotation_mode = "QUATERNION"
bpy.ops.object.mode_set(mode="OBJECT")
# веса тела: автоматически, без кости меча
arm.bones["Weapon"].use_deform = False
for o in bpy.context.selected_objects:
    o.select_set(False)
body.select_set(True); rig.select_set(True); bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
arm.bones["Weapon"].use_deform = True
# меч — целиком на кости Weapon
for o in bpy.context.selected_objects:
    o.select_set(False)
sw.parent = rig; sw.matrix_parent_inverse = rig.matrix_world.inverted()
vg = sw.vertex_groups.get("Weapon") or sw.vertex_groups.new(name="Weapon")
vg.add(list(range(len(sw.data.vertices))), 1.0, "REPLACE")
m = sw.modifiers.get("Armature") or sw.modifiers.new("Armature", "ARMATURE"); m.object = rig
groups = {g.name: 0 for g in body.vertex_groups}
for v in body.data.vertices:
    for g in v.groups:
        if g.weight > 0.01:
            groups[body.vertex_groups[g.group].name] += 1
unweighted = sum(1 for v in body.data.vertices if not any(g.weight > 0.01 for g in v.groups))
result.update(bones=len(arm.bones), groups=groups, unweighted=unweighted)
