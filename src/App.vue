<script setup lang="ts">
import { ref, computed } from 'vue'
import { Card, InputNumber, Button, FileUpload, Knob, ProgressSpinner } from 'openvue'

const objId = ref<number | undefined>()
const probability = ref<number>(95)
const loading = ref<boolean>(false)
const error = ref<boolean>(false)
const showResult = ref<boolean>(false)

declare type Probability = 'HIGH' | 'MEDIUM' | 'LOW'

const knobColor = computed((): string => {
  const _probability = getProbability()
  if (_probability === 'HIGH') {
    return '#dc2626'
  } else if (_probability === 'MEDIUM') {
    return '#f59e0b'
  }
  return '#22c55e'
})

const propbabilityText = computed((): string => {
  const _probability = getProbability()
  if (_probability === 'HIGH') {
    return 'Высокая'
  } else if (_probability === 'MEDIUM') {
    return 'Средняя'
  }
  return 'Низкая'
})

const getProbability = (): Probability => {
  if (probability.value >= 66) {
    return 'HIGH'
  } else if (probability.value >= 33) {
    return 'MEDIUM'
  }
  return 'LOW'
}

const calculate = async () => {
  showResult.value = true
  loading.value = true
  loading.value = false
}
</script>

<template>
  <div class="container">
    <div class="content">
      <div class="full-width">
        <h1>Оценка вероятности банкротства физлица</h1>
        <div>Для рассчета укажите ID объекта из датасета или загрузите csv файл</div>
      </div>

      <Card>
        <template #subtitle>ID объекта</template>
        <template #content>
          <div class="card-content control-content">
            <InputNumber v-model="objId" allow-empty :use-grouping="false" fluid></InputNumber>
            <div>
              <Button label="Рассчитать" :disabled="loading || !objId" @click="calculate"></Button>
            </div>
          </div>
        </template>
      </Card>

      <Card>
        <template #subtitle>Загрузить CSV</template>
        <template #content>
          <FileUpload
            :disabled="loading"
            name="demo[]"
            :multiple="false"
            accept=".csv"
            :max-file-size="10485760"
            choose-label="Выбрать"
            :choose-button-props="{ outlined: true }"
            upload-label="Обработать"
            cancel-label="Очистить"
            @upload="calculate"
          >
            <template #empty>
              <div>Перетащите файлы для загрузки</div>
              <div>или воспользуйтесь кнопкой Выбрать</div>
            </template>
          </FileUpload>
        </template>
      </Card>

      <Card v-if="showResult" class="full-width">
        <template #title>Вероятность банкротства</template>
        <template #content>
          <div class="card-content result-content">
            <template v-if="loading">
              <ProgressSpinner
                style="width: 100px; height: 100px"
                stroke-width="4"
              ></ProgressSpinner>
              <div>Данные обрабатываются</div>
            </template>
            <template v-else-if="error">
              <i class="oi oi-times-circle error-icon"></i>
              <div>Произошла ошибка при расчете</div>
            </template>
            <template v-else>
              <div class="result-content-column">
                <Knob
                  v-model="probability"
                  :size="150"
                  readonly
                  :value-color="knobColor"
                  :text-color="knobColor"
                  value-template="{value}%"
                ></Knob>
                <h3>{{ propbabilityText }}</h3>
              </div>

              <!-- <div class="result-content-details">
                <div>По причине:</div>
                <ul>
                  <li>Лох</li>
                  <li>Нищеброд</li>
                </ul>
              </div> -->
            </template>
          </div>
        </template>
      </Card>
    </div>
  </div>
</template>

<style>
.container {
  padding: 1rem;
  display: flex;
  justify-content: center;
}

.content {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 2rem 1rem;
}

.full-width {
  grid-column: 1 / 3;
}

.card-content {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.control-content {
  height: 100%;
  flex-direction: row;
  justify-content: space-between;
  align-items: center;
}

.result-content {
  display: flex;
  flex-direction: row;
  justify-content: center;
  align-items: start;
  gap: 5rem;
}

.result-content-column {
  display: flex;
  justify-content: center;
  align-items: center;
  flex-direction: column;
}

.error-icon {
  font-size: 3rem;
  color: #dc2626;
}
</style>
