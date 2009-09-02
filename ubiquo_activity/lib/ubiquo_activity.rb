require 'ubiquo_activity/extensions'
module UbiquoActivity
  autoload :StoreActivity, 'ubiquo_activity/store_activity'
  autoload :RegisterActivity, 'ubiquo_activity/register_activity'  
end
Ubiquo::Extensions::UbiquoAreaController.append_include(UbiquoActivity::StoreActivity)
Ubiquo::Extensions::UbiquoAreaController.append_include(UbiquoActivity::RegisterActivity)