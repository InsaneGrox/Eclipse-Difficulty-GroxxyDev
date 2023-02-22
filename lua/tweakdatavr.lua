-- remove vr dmg resistance
Hooks:PostHook(TweakDataVR, "init", "eclipse_init", function(self)
	self.long_range_damage_reduction = {0, 0}
end)

--remove perk deck dash bonuses
--this made me want to commit kingpin green dozer, it somehow took me hours to make this code work.
TweakDataVR.init_specializations = function(self, tweak_data)
end

--remove skill tree dash bonuses
--I was going to just remove this block, but payday 2 crashing has forced my hand, no clue what's even keeping the game alive at this point but I'm too afraid to remove anything else.
TweakDataVR.init_skills = function(self, tweak_data)
	self.post_warp = {
		min = 1,
		max = 5
	}
	self.steelsight_stamina_regen = 0.02

	if _G.IS_VR then --no
	end

	local stamina_regen_macro = tostring(self.steelsight_stamina_regen * 100) .. "%"
	self.skill_descs_addons = { --heck off
	}
end

--I have a question, why do Hooks:OverrideFunction operations not work for these?