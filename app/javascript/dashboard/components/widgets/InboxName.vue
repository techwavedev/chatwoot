<script setup>
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import { computed } from 'vue';

const props = defineProps({
  inbox: {
    type: Object,
    default: () => {},
  },
  withPhoneNumber: {
    type: Boolean,
    default: false,
  },
  withProviderConnectionStatus: {
    type: Boolean,
    default: false,
  },
});

const providerConnection = computed(() => {
  return props.inbox.provider_connection?.connection;
});
</script>

<template>
  <div class="flex items-center text-n-slate-11 text-xs min-w-0">
    <ChannelIcon
      :inbox="inbox"
      class="size-3 ltr:mr-1 rtl:ml-1 flex-shrink-0"
    />
    <span class="truncate">
      {{ inbox.name }}
    </span>
    <span v-if="withPhoneNumber" class="ml-2 text-n-slate-12">{{
      inbox.phone_number
    }}</span>
    <span v-if="withProviderConnectionStatus" class="ml-2">
      <fluent-icon
        icon="circle"
        type="filled"
        :class="
          providerConnection === 'open' ? 'text-green-500' : 'text-n-slate-8'
        "
      />
    </span>
  </div>
</template>
