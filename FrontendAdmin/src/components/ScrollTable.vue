<script setup lang="ts">
import { Table } from 'tdesign-vue-next';

defineOptions({ inheritAttrs: false });
</script>
<template>
  <div class="scroll-table">
    <!-- Enable TDesign's fixed table header; the shared flex layout assigns the actual remaining height. -->
    <Table v-bind="$attrs" :height="$attrs.height as string | number || '100%'">
      <template v-for="(_,name) in $slots" #[name]="scope"><slot :name="name" v-bind="scope || {}" /></template>
    </Table>
  </div>
</template>
