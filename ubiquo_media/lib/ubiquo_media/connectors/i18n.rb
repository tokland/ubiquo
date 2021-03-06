module UbiquoMedia
  module Connectors
    class I18n < Standard

      # Validates the ubiquo_i18n-related dependencies
      def self.validate_requirements
        unless Ubiquo::Plugin.registered[:ubiquo_i18n]
          raise ConnectorRequirementError, "You need the ubiquo_i18n plugin to load #{self}"
        end
        [::AssetRelation].each do |klass|
          if klass.table_exists?
            klass.reset_column_information
            columns = klass.columns.map(&:name).map(&:to_sym)
            unless [:locale, :content_id].all?{|field| columns.include? field}
              if Rails.env.test?
                ::ActiveRecord::Base.connection.change_table(klass.table_name, :translatable => true){}
                klass.reset_column_information
              else
                raise ConnectorRequirementError,
                  "The #{klass.table_name} table does not have the i18n fields. " +
                  "To use this connector, update the table enabling :translatable => true"
              end
            end
          end
        end
      end

      def self.unload!
        ::AssetRelation.untranslatable
        ::AssetRelation.reflections.map(&:first).each do |reflection|
          ::AssetRelation.unshare_translations_for reflection
        end
      end

      module AssetRelation

        def self.included(klass)
          klass.send(:extend, ClassMethods)
          klass.send(:include, InstanceMethods)
          klass.send(:translatable, :name, :position)
          klass.send(:share_translations_for, :asset, :related_object)
          I18n.register_uhooks klass, ClassMethods, InstanceMethods
        end

        module InstanceMethods
          def uhook_set_attribute_values
            existing = related_object.send("#{field_name}_asset_relations").select do |ar|
              ar.asset_id == asset_id
            end.first
            if existing
              # Due to a rails dubious behaviour, it is possible to reach here in
              # some circumstances (if an association has been loaded before the save).
              # Being here means that an AssetRelation is being created automatically
              # and that this AR would be a duplicate of an existing translation.
              # As we have the policy of no repeated assets inside a media_attachment,
              # they should have the same content_id
              write_attribute :content_id, existing.content_id
            end
          end
        end

        module ClassMethods

          # Applies any required extra scope to the filtered_search method
          def uhook_filtered_search filters = {}
            filter_locale = filters[:locale] ?
              {:find => {:conditions => ["asset_relations.locale <= ?", filters[:locale]]}} : {}

            with_scope(filter_locale) do
              yield
            end
          end

          # Returns default values for automatically created Asset Relations
          def uhook_default_values owner, reflection
            if owner.class.is_translatable?
              {:locale => owner.locale}
            else
              {}
            end
          end
        end
      end

      module Migration

        def self.included(klass)
          klass.send(:extend, ClassMethods)
          I18n.register_uhooks klass, ClassMethods
        end

        module ClassMethods
          include Standard::Migration::ClassMethods

          def uhook_create_asset_relations_table
            create_table :asset_relations, :translatable => true do |t|
              yield t
            end
          end
        end
      end

      module ActiveRecord
        module Base

          def self.included(klass)
            klass.send(:extend, ClassMethods)
            klass.send(:include, InstanceMethods)
            I18n.register_uhooks klass, ClassMethods, InstanceMethods
            update_reflections_for_uhook_media_attachment
          end

          # Updates the needed reflections to activate the :translation_shared flag
          def self.update_reflections_for_uhook_media_attachment
            ClassMethods.module_eval do
              module_function :uhook_media_attachment_process_call
            end
            I18n.get_uhook_calls(:uhook_media_attachment).flatten.each do |call|
              ClassMethods.uhook_media_attachment_process_call call
            end
          end

          module ClassMethods
            # called after a media_attachment has been defined and built
            def uhook_media_attachment field, options
              parameters = {:klass => self, :field => field, :options => options}
              I18n.register_uhook_call(parameters) {|call| call.first[:klass] == self && call.first[:field] == field}
              uhook_media_attachment_process_call parameters
            end

            protected

            def uhook_media_attachment_process_call parameters
              # pass all the options
              field, klass, options = parameters.values_at(:field, :klass, :options)
              if options[:translation_shared]
                klass.share_translations_for(field, :"#{field}_asset_relations")
              elsif options[:translation_shared_on_initialize]
                klass.initialize_translations_for(field, :"#{field}_asset_relations")
              end
            end
          end

          module InstanceMethods
            include Standard::ActiveRecord::Base::InstanceMethods

            # we should reject the duplications, objects may contain asset_relations
            # and one of its translations and we only want to keep one
            # we may receive asset_relations or assets
            def uhook_current_asset_relations objects
              objects.reject do |object|
                object.new_record? && object.class.is_translatable? && object.translations.present?
              end
            end
          end
        end
      end
    end
  end
end
